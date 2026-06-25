defmodule Bedrock.Compliance.IngestNormalizerTest do
  @moduledoc """
  Regression coverage for the PR-A normalizer / pinned field contract (ADR-0011):
  the first gate coerces every record to one known shape and **quarantines** a
  record that fails validation — a visible data-quality signal — instead of
  crashing the batch or feeding a Control a value it would misjudge. Driven through
  the single `ingest_events` seam, asserting on resulting domain state.
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

  describe "a record whose amount_total breaks the field contract" do
    test "is quarantined, opens no false Violation, and the rest of the batch still proceeds", %{
      org: org,
      connection: connection
    } do
      batch = [
        # `amount_total` arrives as a string — a field-contract breach. In Elixir's
        # term order a string compares greater than any number, so feeding it to
        # ThresholdApproval would raise a false Violation. The normalizer must
        # quarantine it before any Control sees it.
        %{type: :purchase_order, id: "BAD", vendor_id: "V9", amount_total: "300000000"},
        # A genuine duplicate-vendor breach in the *same* batch must still open.
        %{type: :vendor, id: "V1", name: "Acme Supplies", tax_id: "0101234567"},
        %{type: :vendor, id: "V2", name: "ACME Supplies Co", tax_id: "0101234567"}
      ]

      assert {:ok, [case_record]} = ingest(connection, batch, org)

      case_record = Ash.load!(case_record, [:violation], tenant: org)
      assert case_record.violation.control_name == "Duplicate Vendor"

      # The bad PO never reached a Control: exactly one Case, none from "BAD".
      assert length(Compliance.list_cases!(tenant: org)) == 1

      # The breach is a visible, queryable data-quality signal carrying the offender.
      assert [entry] = Compliance.list_quarantine_entries!(tenant: org)
      assert entry.reason =~ "amount_total"
      assert entry.raw["id"] == "BAD"
    end

    test "a float or Decimal amount_total is quarantined too — never a lossy coercion", %{
      org: org,
      connection: connection
    } do
      # A float is lossy and a bare Decimal carries no currency: both break the
      # `integer | Money` contract and must be quarantined, not silently coerced.
      batch = [
        %{type: :purchase_order, id: "FLT", vendor_id: "V9", amount_total: 3.0e8},
        %{
          type: :purchase_order,
          id: "DEC",
          vendor_id: "V9",
          amount_total: Decimal.new("300000000")
        }
      ]

      assert {:ok, []} = ingest(connection, batch, org)

      assert [] = Compliance.list_cases!(tenant: org)
      assert [] = Compliance.list_process_instances!(tenant: org)

      ids = Enum.map(Compliance.list_quarantine_entries!(tenant: org), & &1.raw["id"])
      assert "FLT" in ids
      assert "DEC" in ids
    end
  end

  describe "monetary fields are Money, evaluated per-currency" do
    test "Split PO never pools amounts across currencies", %{org: org, connection: connection} do
      # Two 300M orders to one vendor in-window, but in different currencies. Pooled
      # naively they would breach the 500M threshold; evaluated per-currency (ADR-0011)
      # neither currency reaches it, so no split is raised.
      batch = [
        %{
          type: :purchase_order,
          id: "PO1",
          vendor_id: "V1",
          amount_total: 300_000_000,
          currency: "VND",
          order_date: ~U[2026-01-01 09:00:00Z]
        },
        %{
          type: :purchase_order,
          id: "PO2",
          vendor_id: "V1",
          amount_total: 300_000_000,
          currency: "USD",
          order_date: ~U[2026-01-02 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, batch, org)
      assert [] = Compliance.list_cases!(tenant: org)
    end

    test "the persisted Event carries the amount as a per-currency Money", %{
      org: org,
      connection: connection
    } do
      batch = [
        %{type: :purchase_order, id: "PO9", amount_total: 100_000_000, currency: "VND"}
      ]

      assert {:ok, _} = ingest(connection, batch, org)

      assert [event] = Compliance.list_events!(tenant: org)
      assert event.payload["amount_total"] == %{"amount" => "100000000", "currency" => "VND"}
    end
  end
end
