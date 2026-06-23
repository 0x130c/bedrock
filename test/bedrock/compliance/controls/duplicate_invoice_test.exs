defmodule Bedrock.Compliance.Controls.DuplicateInvoiceTest do
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Controls.DuplicateInvoice

  defp bill(attrs), do: Map.merge(%{type: :vendor_bill}, attrs)

  describe "findings/2" do
    test "two bills from the same vendor with the same invoice number are flagged once" do
      records = [
        bill(%{id: "B1", vendor_id: "V1", invoice_number: "INV-001", amount_total: 12_000_000}),
        bill(%{id: "B2", vendor_id: "V1", invoice_number: "INV-001", amount_total: 12_000_000})
      ]

      assert [finding] = DuplicateInvoice.findings(records, [])

      assert finding.reason =~ "Duplicate Invoice"
      assert finding.reason =~ "INV-001"
      assert finding.reason =~ "B1"
      assert finding.reason =~ "B2"

      assert MapSet.new(Enum.map(finding.evidence.bills, & &1.id)) == MapSet.new(["B1", "B2"])
    end

    test "the same invoice number from different vendors is not a duplicate" do
      records = [
        bill(%{id: "B1", vendor_id: "V1", invoice_number: "INV-001", amount_total: 1}),
        bill(%{id: "B2", vendor_id: "V2", invoice_number: "INV-001", amount_total: 1})
      ]

      assert [] = DuplicateInvoice.findings(records, [])
    end

    test "distinct invoice numbers from one vendor are not duplicates" do
      records = [
        bill(%{id: "B1", vendor_id: "V1", invoice_number: "INV-001", amount_total: 1}),
        bill(%{id: "B2", vendor_id: "V1", invoice_number: "INV-002", amount_total: 1})
      ]

      assert [] = DuplicateInvoice.findings(records, [])
    end
  end
end
