defmodule Bedrock.Compliance.VendorBankChange do
  @moduledoc """
  Poll-only sourcing of the flagship anomaly's trigger (ADR-0011, ADR-0003). The
  bank-account-changed→payment pattern needs a `vendor_change` Event, but a vanilla
  Odoo with no automation installed never *pushes* one. So the seam manufactures it:
  the poller fetches each vendor's `res.partner.bank` as a snapshot, and this module
  **diffs** the polled account number against the last-known snapshot in the Event
  History, synthesizing a `:vendor_change` (`field: :bank_account`, the before/after
  values, `occurred_at` = the bank record's `write_date`) whenever it moved.

  The synthesized change is an ordinary Event from there on — persisted to the Event
  History and correlated across batches like any other — so the flagship anomaly
  fires on stock Odoo with nothing installed; the optional webhook (ADR-0003) only
  lowers latency, never gates detection. The first time a bank record is seen there
  is nothing to diff against, so no change is synthesized.
  """
  require Ash.Query

  alias Bedrock.Compliance
  alias Bedrock.Compliance.{EventHistory, Normalizer}

  @doc """
  Synthesize the `:vendor_change` records implied by the `:vendor_bank` snapshots in
  `records`, diffing each against the last-known snapshot persisted in the tenant's
  Event History. Returns `[]` when the batch carries no bank snapshot or none moved.

  Must run *before* the batch is upserted into the Event History, so the diff reads
  the prior value rather than the one just polled.
  """
  @spec synthesize([map()], term()) :: [map()]
  def synthesize(records, tenant) do
    case Enum.filter(records, &bank_snapshot?/1) do
      [] -> []
      snapshots -> Enum.flat_map(snapshots, &change_for(&1, last_known(snapshots, tenant)))
    end
  end

  # The last-known snapshot of each bank record the batch re-polled, keyed by the
  # same semantic key the snapshot will upsert under, rehydrated to the read shape.
  defp last_known(snapshots, tenant) do
    keys = for snapshot <- snapshots, {:ok, key} <- [Normalizer.event_key(snapshot)], do: key

    Compliance.Event
    |> Ash.Query.filter(natural_key in ^keys)
    |> Ash.read!(tenant: tenant)
    |> Map.new(fn event -> {event.natural_key, EventHistory.rehydrate(event)} end)
  end

  defp change_for(snapshot, prior_by_key) do
    with {:ok, key} <- Normalizer.event_key(snapshot),
         %{} = prior <- Map.get(prior_by_key, key),
         {old, new} when old != new <- {account(prior), account(snapshot)} do
      [
        %{
          type: :vendor_change,
          vendor_id: Map.get(snapshot, :vendor_id),
          field: :bank_account,
          old_value: old,
          new_value: new,
          occurred_at: Map.get(snapshot, :write_date)
        }
      ]
    else
      _no_change -> []
    end
  end

  defp account(record), do: Map.get(record, :acc_number)

  defp bank_snapshot?(record), do: Map.get(record, :type) == :vendor_bank
end
