defmodule Bedrock.Compliance.EventHistory do
  @moduledoc """
  The read side of the tenant-scoped Event History (ADR-0011, Slice B) — the
  substrate that lets the *pure*, parameter-free detectors (ADR-0006) correlate
  *across* Ingest Batches without ever querying a store themselves. Under the v1
  poller one P2P process is naturally split across many polls; rather than make a
  detector stateful, the seam hands it the relevant recent history alongside the
  new batch and lets the same pure function run over the longer list.

  `window/3` is that hand-off. Given the current batch, the tenant, and a
  detector's correlation spec, it:

    1. computes the *touched* correlation keys present in the batch (e.g. the
       vendors a payment names, the POs an event references);
    2. loads the bounded recent history for exactly those keys from the persisted
       Event History — its `event_type`s and a `:lookback` horizon push to the
       query, the per-key match is applied after rehydration;
    3. **rehydrates** each stored Event back to the normalized in-memory shape the
       detectors read — the `Event.payload` round-trips through `jsonb`, so atoms,
       `DateTime`s, `Money` and `Decimal` come back as strings/maps and must be
       coerced back to the pinned field contract; and
    4. merges history with the batch, de-duplicated by the semantic key so the
       batch's own (fresher, in-memory) copy of a fact wins over its persisted one.

  A spec with `lookback: :none` (the default for a detector that has not opted into
  cross-batch correlation) yields the batch unchanged, preserving single-batch
  behaviour.
  """
  require Ash.Query

  alias Bedrock.Compliance
  alias Bedrock.Compliance.Normalizer

  @typedoc """
  A detector's correlation spec (ADR-0011 "per-detector window"):

    * `:types` — the Event types this detector correlates over (`:all` for every
      type), used to bound both the touched-key scan and the history query.
    * `:key` — a function mapping a normalized record to its correlation key (the
      bucket a window groups by — a vendor id, a `po_ref`), or `nil` when the
      record carries no such key.
    * `:lookback` — how far back to replay: `:none` (batch only), a `{n, unit}`
      duration (`:hour` / `:day`), or `:full` (entity-complete, capped at 12 months).
  """
  @type spec :: %{
          types: [atom()] | :all,
          key: (map() -> term() | nil),
          lookback: :none | {pos_integer(), :hour | :day} | :full
        }

  # `:full` is entity-complete but capped so a never-terminating journey cannot
  # replay unboundedly (ADR-0011).
  @full_cap_days 365

  @doc """
  The replay window for `records` under a detector's correlation `spec`: the batch
  merged with the bounded Event History of the correlation keys the batch touched,
  rehydrated to the normalized shape. Returns the batch unchanged for a
  `lookback: :none` spec or when the batch touches no correlation key.
  """
  @spec window([map()], term(), spec()) :: [map()]
  def window(records, tenant, spec) do
    touched = touched_keys(records, spec)

    if spec.lookback == :none or Enum.empty?(touched) do
      records
    else
      merge(records, load_history(tenant, spec, touched, records))
    end
  end

  @doc """
  Rehydrate a persisted `Event` (or a raw `jsonb` payload) back to the normalized
  in-memory record the pure detectors read — inverting the `jsonb` round-trip so
  `:type`/`:field` are atoms again, timestamps are `DateTime`s, monetary fields are
  `Money`, and quantities are `Decimal`.
  """
  @spec rehydrate(map()) :: map()
  def rehydrate(%{payload: payload}), do: rehydrate(payload)

  def rehydrate(payload) when is_map(payload) do
    Map.new(payload, fn {key, value} ->
      atom = atom_key(key)
      {atom, rehydrate_value(atom, value)}
    end)
  end

  # The semantic key of every key-carrying record in the batch whose type this
  # detector correlates over — the buckets whose history is worth replaying.
  defp touched_keys(records, spec) do
    records
    |> Enum.filter(&type_match?(&1, spec.types))
    |> Enum.map(spec.key)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp load_history(tenant, spec, touched, records) do
    spec
    |> history_query(records)
    |> Ash.read!(tenant: tenant)
    |> Enum.map(&rehydrate/1)
    |> Enum.filter(fn record -> MapSet.member?(touched, spec.key.(record)) end)
  end

  defp history_query(spec, records) do
    Compliance.Event
    |> filter_types(spec.types)
    |> filter_lookback(cutoff(spec.lookback, records))
  end

  defp filter_types(query, :all), do: query

  defp filter_types(query, types) do
    type_strings = Enum.map(types, &to_string/1)
    Ash.Query.filter(query, event_type in ^type_strings)
  end

  defp filter_lookback(query, nil), do: query

  defp filter_lookback(query, cutoff) do
    Ash.Query.filter(query, is_nil(occurred_at) or occurred_at >= ^cutoff)
  end

  # The earliest occurrence still inside the lookback horizon, measured back from
  # the batch's latest timestamp. `nil` when the horizon cannot be computed (the
  # batch carries no timestamp), in which case no time bound is pushed to the query.
  defp cutoff(:full, records), do: cutoff({@full_cap_days, :day}, records)

  defp cutoff({n, unit}, records) do
    case reference_time(records) do
      nil -> nil
      reference -> DateTime.add(reference, -seconds(n, unit), :second)
    end
  end

  defp seconds(n, :hour), do: n * 3600
  defp seconds(n, :day), do: n * 86_400

  defp reference_time(records) do
    records
    |> Enum.map(&(Map.get(&1, :occurred_at) || Map.get(&1, :order_date)))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  # Batch first, so a fact present in both the batch and the just-persisted history
  # keeps the batch's in-memory copy. Records with no derivable semantic key cannot
  # collide, so each is kept.
  defp merge(records, history) do
    Enum.uniq_by(records ++ history, &dedup_key/1)
  end

  defp dedup_key(record) do
    case Normalizer.event_key(record) do
      {:ok, key} -> key
      :error -> {:no_key, record}
    end
  end

  defp type_match?(_record, :all), do: true
  defp type_match?(record, types), do: Map.get(record, :type) in types

  defp atom_key(key) when is_atom(key), do: key

  defp atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp rehydrate_value(key, value) when key in [:type, :field] and is_binary(value),
    do: String.to_existing_atom(value)

  defp rehydrate_value(key, value)
       when key in [:occurred_at, :order_date, :write_date] and is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp rehydrate_value(key, %{"amount" => amount, "currency" => currency})
       when key in [:amount_total, :unit_price],
       do: Money.new(currency, Decimal.new(amount))

  defp rehydrate_value(:quantity, value) when is_binary(value), do: Decimal.new(value)

  defp rehydrate_value(:approvals, value) when is_list(value),
    do: Enum.map(value, &rehydrate/1)

  defp rehydrate_value(_key, value), do: value
end
