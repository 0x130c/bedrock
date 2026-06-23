defmodule Bedrock.Compliance.ProcessInstanceTest do
  @moduledoc """
  Unit coverage of reconstructing a `ProcessInstance` — one PO's actual journey —
  from a batch of normalized Odoo records. Pure: events in, ordered activities
  out, no database.
  """
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.ProcessInstance

  describe "reconstruct/1" do
    test "orders a PO's activities by occurrence, regardless of input order" do
      records = [
        %{type: :payment, po_ref: "PO1", occurred_at: ~U[2026-02-04 09:00:00Z]},
        %{
          type: :purchase_order,
          id: "PO1",
          amount_total: 100_000_000,
          order_date: ~U[2026-02-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{type: :vendor_bill, po_ref: "PO1", occurred_at: ~U[2026-02-03 09:00:00Z]},
        %{type: :goods_receipt, po_ref: "PO1", occurred_at: ~U[2026-02-02 09:00:00Z]}
      ]

      assert [instance] = ProcessInstance.reconstruct(records)
      assert instance.po_ref == "PO1"

      assert Enum.map(instance.activities, & &1.activity) ==
               [:approve, :receive_goods, :bill, :pay]
    end

    test "a PO with no recorded approval reconstructs without an approve activity" do
      records = [
        %{
          type: :purchase_order,
          id: "PO9",
          amount_total: 10_000_000,
          order_date: ~U[2026-02-01 09:00:00Z]
        },
        %{type: :goods_receipt, po_ref: "PO9", occurred_at: ~U[2026-02-02 09:00:00Z]}
      ]

      assert [instance] = ProcessInstance.reconstruct(records)
      assert Enum.map(instance.activities, & &1.activity) == [:receive_goods]
    end
  end
end
