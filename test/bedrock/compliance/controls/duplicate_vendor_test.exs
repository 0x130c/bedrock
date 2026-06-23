defmodule Bedrock.Compliance.Controls.DuplicateVendorTest do
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Controls.DuplicateVendor

  defp vendor(attrs), do: Map.merge(%{type: :vendor}, attrs)

  describe "findings/2" do
    test "two vendors sharing a tax id are flagged once, naming the control and both vendors" do
      records = [
        vendor(%{id: "V1", name: "Acme Supplies", tax_id: "0101234567"}),
        vendor(%{id: "V2", name: "ACME Supplies Co", tax_id: "0101234567"})
      ]

      assert [finding] = DuplicateVendor.findings(records, [])

      assert finding.reason =~ "Duplicate Vendor"
      assert finding.reason =~ "0101234567"
      assert finding.reason =~ "V1"
      assert finding.reason =~ "V2"

      assert MapSet.new(Enum.map(finding.evidence.vendors, & &1.id)) ==
               MapSet.new(["V1", "V2"])
    end

    test "two vendors sharing a bank account but with different tax ids are flagged" do
      records = [
        vendor(%{id: "V1", name: "Acme", tax_id: "0101111111", bank_account: "VN98 7654"}),
        vendor(%{id: "V2", name: "Globex", tax_id: "0202222222", bank_account: "VN98 7654"})
      ]

      assert [finding] = DuplicateVendor.findings(records, [])
      assert finding.reason =~ "bank_account"
      assert finding.reason =~ "VN98 7654"
    end

    test "vendors with distinct identities raise nothing" do
      records = [
        vendor(%{id: "V1", name: "Acme", tax_id: "0101111111", bank_account: "VN01"}),
        vendor(%{id: "V2", name: "Globex", tax_id: "0202222222", bank_account: "VN02"})
      ]

      assert [] = DuplicateVendor.findings(records, [])
    end

    test "an exempt vendor is excluded from collision detection" do
      records = [
        vendor(%{id: "V1", name: "Acme", tax_id: "0101234567"}),
        vendor(%{id: "V2", name: "Acme Clone", tax_id: "0101234567"})
      ]

      assert [] = DuplicateVendor.findings(records, exempt_vendors: ["V2"])
    end
  end
end
