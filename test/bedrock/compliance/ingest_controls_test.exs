defmodule Bedrock.Compliance.IngestControlsTest do
  @moduledoc """
  Domain-level coverage of the deterministic P2P Control library, driven through
  the single `ingest_events` seam with fixtures (no real Odoo). Each test asserts
  on resulting domain state — the Case/Violation/HardEvidence that now exist —
  never on private functions or the dispatch internals.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance

  setup do
    org =
      Compliance.create_organization!(%{name: "Acme #{System.unique_integer([:positive])}"})

    connection =
      Compliance.create_connection!(
        %{name: "Primary", odoo_url: "https://acme.odoo.com", credential: "ro-secret"},
        tenant: org
      )

    %{org: org, connection: connection}
  end

  defp ingest(connection, records, org),
    do: Compliance.ingest_events(connection, records, tenant: org)

  describe "Duplicate Vendor" do
    test "two vendors sharing a tax id open one Case naming the Control", %{
      org: org,
      connection: connection
    } do
      vendors = [
        %{type: :vendor, id: "V1", name: "Acme Supplies", tax_id: "0101234567"},
        %{type: :vendor, id: "V2", name: "ACME Supplies Co", tax_id: "0101234567"}
      ]

      assert {:ok, [case_record]} = ingest(connection, vendors, org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)

      assert case_record.violation.control_name == "Duplicate Vendor"
      assert case_record.violation.reason =~ "0101234567"
      assert length(case_record.hard_evidence.snapshot["vendors"]) == 2
    end
  end

  describe "Duplicate Invoice" do
    test "the same vendor bill ingested twice opens one Case naming the Control", %{
      org: org,
      connection: connection
    } do
      bills = [
        %{
          type: :vendor_bill,
          id: "B1",
          vendor_id: "V1",
          invoice_number: "INV-001",
          amount_total: 12_000_000
        },
        %{
          type: :vendor_bill,
          id: "B2",
          vendor_id: "V1",
          invoice_number: "INV-001",
          amount_total: 12_000_000
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, bills, org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)

      assert case_record.violation.control_name == "Duplicate Invoice"
      assert case_record.violation.reason =~ "INV-001"
      assert length(case_record.hard_evidence.snapshot["bills"]) == 2
    end
  end

  describe "Split PO" do
    test "sub-threshold POs to one vendor in-window combining over the threshold open one Case",
         %{
           org: org,
           connection: connection
         } do
      orders = [
        %{
          type: :purchase_order,
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-01 09:00:00Z]
        },
        %{
          type: :purchase_order,
          id: "PO2",
          vendor_id: "V1",
          amount_total: 300_000_000,
          order_date: ~U[2026-01-02 09:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, orders, org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)

      assert case_record.violation.control_name == "Split PO"
      assert case_record.violation.reason =~ "V1"
      assert case_record.hard_evidence.snapshot["combined_total"] == 600_000_000
    end
  end

  describe "Three-Way Match" do
    test "a bill for more than was received opens one Case naming the Control", %{
      org: org,
      connection: connection
    } do
      records = [
        # Approval present so the journey conforms — isolating this to the 3-way match.
        %{
          type: :purchase_order,
          id: "PO1",
          quantity: 100,
          unit_price: 50_000,
          approvals: [%{role: "CFO"}]
        },
        %{type: :goods_receipt, po_ref: "PO1", quantity: 100},
        %{type: :vendor_bill, po_ref: "PO1", quantity: 120, unit_price: 50_000}
      ]

      assert {:ok, [case_record]} = ingest(connection, records, org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)

      assert case_record.violation.control_name == "Three-Way Match"
      assert case_record.violation.reason =~ "PO1"
      assert "quantity" in case_record.hard_evidence.snapshot["mismatches"]
    end
  end

  describe "clean data" do
    test "a clean heterogeneous batch opens no Cases across the whole Control library", %{
      org: org,
      connection: connection
    } do
      records = [
        # An approved, sub-threshold PO with a matching receipt and bill (clean 3-way).
        %{
          type: :purchase_order,
          id: "PO1",
          vendor_id: "VA",
          amount_total: 400_000_000,
          currency: "VND",
          quantity: 100,
          unit_price: 4_000_000,
          order_date: ~U[2026-01-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{type: :goods_receipt, po_ref: "PO1", quantity: 100},
        %{
          type: :vendor_bill,
          po_ref: "PO1",
          vendor_id: "VA",
          invoice_number: "INV-100",
          quantity: 100,
          unit_price: 4_000_000
        },
        # Two genuinely distinct vendors.
        %{type: :vendor, id: "V1", name: "Acme", tax_id: "0101111111", bank_account: "VN01"},
        %{type: :vendor, id: "V2", name: "Globex", tax_id: "0202222222", bank_account: "VN02"}
      ]

      assert {:ok, []} = ingest(connection, records, org)
      assert [] = Compliance.list_cases!(tenant: org)
    end
  end
end
