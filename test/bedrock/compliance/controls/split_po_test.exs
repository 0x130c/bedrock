defmodule Bedrock.Compliance.Controls.SplitPoTest do
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Controls.SplitPo

  defp po(attrs), do: Map.merge(%{type: :purchase_order}, attrs)

  @opts [threshold: 500_000_000, window_hours: 72]

  describe "findings/2" do
    test "two sub-threshold POs to one vendor within the window that combine over the threshold are flagged" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        }),
        po(%{
          id: "PO2",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-02 09:00:00Z]
        })
      ]

      assert [finding] = SplitPo.findings(records, @opts)

      assert finding.reason =~ "Split"
      assert finding.reason =~ "V1"
      assert finding.reason =~ "PO1"
      assert finding.reason =~ "PO2"

      assert MapSet.new(Enum.map(finding.evidence.orders, & &1.id)) == MapSet.new(["PO1", "PO2"])
      assert finding.evidence.combined_total == 600_000_000
    end

    test "sub-threshold POs spread beyond the window are not a split" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        }),
        po(%{
          id: "PO2",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-10 09:00:00Z]
        })
      ]

      assert [] = SplitPo.findings(records, @opts)
    end

    test "a single PO is never a split, even above the threshold" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 900_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        })
      ]

      assert [] = SplitPo.findings(records, @opts)
    end

    test "two in-window POs whose combined stays under the threshold are not a split" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 100_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        }),
        po(%{
          id: "PO2",
          vendor_id: "V1",
          amount_total: 100_000_000,
          order_date: ~U[2026-01-01 18:00:00Z]
        })
      ]

      assert [] = SplitPo.findings(records, @opts)
    end

    test "in-window POs split across two vendors are not pooled together" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        }),
        po(%{
          id: "PO2",
          vendor_id: "V2",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 12:00:00Z]
        })
      ]

      assert [] = SplitPo.findings(records, @opts)
    end

    test "the offending vendor can be exempted" do
      records = [
        po(%{
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        }),
        po(%{
          id: "PO2",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-02 09:00:00Z]
        })
      ]

      assert [] = SplitPo.findings(records, Keyword.put(@opts, :exempt_vendors, ["V1"]))
    end
  end
end
