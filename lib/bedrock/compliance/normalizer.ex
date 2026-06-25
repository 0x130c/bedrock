defmodule Bedrock.Compliance.Normalizer do
  @moduledoc """
  The first gate of the ingestion seam (ADR-0011). Every incoming record is coerced
  to one pinned field contract before any Control, reconstruction, or detector sees
  it, and a record that breaks the contract is **quarantined** — pulled out of the
  batch with a human-readable reason — so a single malformed record never crashes
  the batch and never reaches a Control that would misjudge it. Controls then read
  one known shape and shed their defensive type guards.

  Pure: records in, `{valid, quarantined}` out, no database. The seam persists the
  quarantined entries as a data-quality signal.

  The contract pinned here:

    * Monetary fields (`amount_total`, `unit_price`) are coerced to an `ash_money`
      `Money` in the record's `:currency` (default `#{:VND}`). A value already a
      `Money` is kept; an integer is wrapped (minor units, as the Odoo adapter
      emits); a string/float/`Decimal` is a contract breach — in Elixir's term order
      a string even compares greater than any number, and a float is lossy.
    * Quantity fields (`quantity`) are coerced to `Decimal`. An integer is wrapped, a
      `Decimal` kept; anything else is a breach.
  """

  @default_currency :VND
  @money_fields [:amount_total, :unit_price]
  @decimal_fields [:quantity]

  @typedoc "A rejected record paired with why it failed the contract."
  @type quarantined :: %{raw: map(), reason: String.t()}

  @doc """
  Split a batch into the records coerced to the field contract and the ones
  quarantined for breaking it, preserving input order in each.
  """
  @spec normalize([map()]) :: {[map()], [quarantined()]}
  def normalize(records) do
    {valid, quarantined} =
      Enum.reduce(records, {[], []}, fn record, {valid, quarantined} ->
        case coerce(record) do
          {:ok, coerced} -> {[coerced | valid], quarantined}
          {:error, reason} -> {valid, [%{raw: record, reason: reason} | quarantined]}
        end
      end)

    {Enum.reverse(valid), Enum.reverse(quarantined)}
  end

  @doc """
  The *semantic* natural key for a record's Event History entry (ADR-0011) — the
  dedup identity the same real-world fact shares across poll and webhook, **not** the
  source-row id. `{model, odoo_id}` for an entity or discrete fact; `{vendor_id,
  field, occurred_at}` for a change fact. Returns `:error` when no stable key can be
  formed (the record is not added to the Event History).
  """
  @spec event_key(map()) :: {:ok, String.t()} | :error
  def event_key(%{type: :vendor_change} = record) do
    vendor_id = Map.get(record, :vendor_id)
    field = Map.get(record, :field)
    occurred_at = Map.get(record, :occurred_at)

    if vendor_id && field && occurred_at do
      {:ok, "vendor_change:#{vendor_id}:#{field}:#{DateTime.to_iso8601(occurred_at)}"}
    else
      :error
    end
  end

  def event_key(%{type: type} = record) when not is_nil(type) do
    case Map.get(record, :id) do
      nil -> :error
      id -> {:ok, "#{type}:#{id}"}
    end
  end

  def event_key(_record), do: :error

  # Coerce every contracted field in turn; the first breach quarantines the record.
  defp coerce(record) do
    currency = Map.get(record, :currency) || @default_currency

    Enum.reduce_while(@money_fields, {:ok, record}, fn field, {:ok, acc} ->
      case coerce_money(acc, field, currency) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
    |> then(&coerce_decimals/1)
  end

  defp coerce_decimals({:error, _} = error), do: error

  defp coerce_decimals({:ok, record}) do
    Enum.reduce_while(@decimal_fields, {:ok, record}, fn field, {:ok, acc} ->
      case coerce_decimal(acc, field) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp coerce_money(record, field, currency) do
    case Map.get(record, field) do
      nil -> {:ok, record}
      %Money{} -> {:ok, record}
      amount when is_integer(amount) -> {:ok, Map.put(record, field, Money.new(currency, amount))}
      other -> {:error, breach(field, other, "an integer (minor units) or Money")}
    end
  end

  defp coerce_decimal(record, field) do
    case Map.get(record, field) do
      nil -> {:ok, record}
      %Decimal{} -> {:ok, record}
      value when is_integer(value) -> {:ok, Map.put(record, field, Decimal.new(value))}
      other -> {:error, breach(field, other, "an integer or Decimal")}
    end
  end

  defp breach(field, value, expected),
    do: "#{field} must be #{expected}, got #{inspect(value)} — field-contract breach"
end
