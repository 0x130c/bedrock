defmodule Bedrock.Compliance.ProcessInstance do
  @moduledoc """
  The actual journey of one Purchase Order, reconstructed from Odoo's event log
  into an ordered sequence of activities and compared against the canonical
  `Process`. NOT a `Case` — it is the trace a Conformance Deviation is found in.
  Tenant-scoped (ADR-0007); persisted so the reconstructed ordered history
  survives even though the ERP cannot be trusted to retain it (ADR-0003/0004).

  `reconstruct/1` is the pure core: a batch of normalized records in, one ordered
  ProcessInstance per PO out, no database. Activities are ordered by occurrence;
  events that share (or lack) a timestamp fall back to canonical Process order so
  an untimed-but-conformant journey is never mistaken for an out-of-order one.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  alias Bedrock.Compliance.Process

  postgres do
    table "process_instances"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:po_ref, :activities]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :po_ref, :string do
      allow_nil? false
      public? true
    end

    # The ordered journey: a list of `%{activity, occurred_at}` maps.
    attribute :activities, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    timestamps()
  end

  @doc """
  Reconstruct one ProcessInstance per Purchase Order from a batch of normalized
  records. Returns plain maps (`%{po_ref, activities}`) with activities ordered by
  occurrence; each activity is `%{activity: atom, occurred_at: DateTime.t() | nil}`.
  """
  def reconstruct(records) do
    by_po_ref = Enum.group_by(records, &Map.get(&1, :po_ref))

    records
    |> Enum.filter(&(Map.get(&1, :type) == :purchase_order))
    |> Enum.map(fn po ->
      related = Map.get(by_po_ref, po.id, [])
      %{po_ref: po.id, activities: order(activities_for(po, related))}
    end)
  end

  defp activities_for(po, related) do
    approval(po) ++ Enum.flat_map(related, &event_activity/1)
  end

  defp approval(po) do
    case Map.get(po, :approvals, []) do
      [] -> []
      _ -> [%{activity: :approve, occurred_at: timestamp(po)}]
    end
  end

  defp event_activity(%{type: :goods_receipt} = record),
    do: [%{activity: :receive_goods, occurred_at: timestamp(record)}]

  defp event_activity(%{type: :vendor_bill} = record),
    do: [%{activity: :bill, occurred_at: timestamp(record)}]

  defp event_activity(%{type: :payment} = record),
    do: [%{activity: :pay, occurred_at: timestamp(record)}]

  defp event_activity(_record), do: []

  defp timestamp(record), do: Map.get(record, :occurred_at) || Map.get(record, :order_date)

  defp order(activities), do: Enum.sort(activities, &before?/2)

  defp before?(a, b) do
    case {a.occurred_at, b.occurred_at} do
      {nil, _} -> index(a.activity) <= index(b.activity)
      {_, nil} -> index(a.activity) <= index(b.activity)
      {ta, tb} -> compare(ta, tb, a.activity, b.activity)
    end
  end

  defp compare(ta, tb, activity_a, activity_b) do
    case DateTime.compare(ta, tb) do
      :eq -> index(activity_a) <= index(activity_b)
      :lt -> true
      :gt -> false
    end
  end

  defp index(activity), do: Enum.find_index(Process.activities(), &(&1 == activity))
end
