defmodule Bedrock.Compliance.Controls.ThreeWayMatchTest do
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Controls.ThreeWayMatch

  defp po(attrs), do: Map.merge(%{type: :purchase_order}, attrs)
  defp gr(attrs), do: Map.merge(%{type: :goods_receipt}, attrs)
  defp bill(attrs), do: Map.merge(%{type: :vendor_bill}, attrs)

  @opts [quantity_tolerance: 0, price_tolerance: 0]

  describe "findings/2" do
    test "a bill for more units than were received is a quantity mismatch" do
      records = [
        po(%{id: "PO1", quantity: 100, unit_price: 50_000}),
        gr(%{po_ref: "PO1", quantity: 100}),
        bill(%{po_ref: "PO1", quantity: 120, unit_price: 50_000})
      ]

      assert [finding] = ThreeWayMatch.findings(records, @opts)

      assert finding.reason =~ "Three-Way Match"
      assert finding.reason =~ "PO1"
      assert :quantity in finding.evidence.mismatches
    end

    test "a bill priced above the PO is a price mismatch" do
      records = [
        po(%{id: "PO1", quantity: 100, unit_price: 50_000}),
        gr(%{po_ref: "PO1", quantity: 100}),
        bill(%{po_ref: "PO1", quantity: 100, unit_price: 60_000})
      ]

      assert [finding] = ThreeWayMatch.findings(records, @opts)
      assert :price in finding.evidence.mismatches
    end

    test "a PO, receipt and bill that agree raise nothing" do
      records = [
        po(%{id: "PO1", quantity: 100, unit_price: 50_000}),
        gr(%{po_ref: "PO1", quantity: 100}),
        bill(%{po_ref: "PO1", quantity: 100, unit_price: 50_000})
      ]

      assert [] = ThreeWayMatch.findings(records, @opts)
    end

    test "a quantity gap within tolerance raises nothing" do
      records = [
        po(%{id: "PO1", quantity: 100, unit_price: 50_000}),
        gr(%{po_ref: "PO1", quantity: 100}),
        bill(%{po_ref: "PO1", quantity: 102, unit_price: 50_000})
      ]

      assert [] = ThreeWayMatch.findings(records, quantity_tolerance: 5, price_tolerance: 0)
    end

    test "partial receipts that sum to the billed quantity agree" do
      records = [
        po(%{id: "PO1", quantity: 100, unit_price: 50_000}),
        gr(%{po_ref: "PO1", quantity: 60}),
        gr(%{po_ref: "PO1", quantity: 40}),
        bill(%{po_ref: "PO1", quantity: 100, unit_price: 50_000})
      ]

      assert [] = ThreeWayMatch.findings(records, @opts)
    end

    test "a bill carrying a PO reference but with no PO or receipt in the batch is not compared" do
      records = [bill(%{po_ref: "PO1", quantity: 120, unit_price: 60_000})]

      assert [] = ThreeWayMatch.findings(records, @opts)
    end
  end
end
