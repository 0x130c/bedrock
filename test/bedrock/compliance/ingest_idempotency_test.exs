defmodule Bedrock.Compliance.IngestIdempotencyTest do
  @moduledoc """
  Regression coverage for the PR-A idempotency contract (ADR-0011): re-ingesting
  the same Ingest Batch must not duplicate domain state. Driven through the single
  `ingest_events` seam, asserting on resulting domain state (Case / ProcessInstance
  counts) — never on private functions or dispatch internals.
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

  describe "re-ingesting the same batch" do
    test "leaves Case and ProcessInstance counts unchanged", %{org: org, connection: connection} do
      # One PO journey (→ one ProcessInstance) carrying a 3-way quantity mismatch
      # (→ one Violation Case). The same real-world facts re-arriving via a poll
      # overlap or an Oban retry must be a no-op, not a second Case / journey.
      batch = [
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

      assert {:ok, [_case]} = ingest(connection, batch, org)
      assert {:ok, _} = ingest(connection, batch, org)

      assert length(Compliance.list_cases!(tenant: org)) == 1
      assert length(Compliance.list_process_instances!(tenant: org)) == 1
    end
  end

  describe "each Control's Violation is idempotent across re-ingest" do
    test "Threshold Approval opens one Case for the same over-threshold PO", ctx do
      batch = [%{type: :purchase_order, id: "PO1", amount_total: 600_000_000}]
      assert_one_case_on_reingest(ctx, batch, "Threshold Approval")
    end

    test "Duplicate Invoice opens one Case for the same colliding bills", ctx do
      batch = [
        %{
          type: :vendor_bill,
          id: "B1",
          vendor_id: "V1",
          invoice_number: "INV-1",
          amount_total: 1
        },
        %{type: :vendor_bill, id: "B2", vendor_id: "V1", invoice_number: "INV-1", amount_total: 1}
      ]

      assert_one_case_on_reingest(ctx, batch, "Duplicate Invoice")
    end

    test "Duplicate Vendor opens one Case for the same colliding vendors", ctx do
      batch = [
        %{type: :vendor, id: "V1", name: "Acme", tax_id: "0101234567"},
        %{type: :vendor, id: "V2", name: "ACME Co", tax_id: "0101234567"}
      ]

      assert_one_case_on_reingest(ctx, batch, "Duplicate Vendor")
    end

    test "Split PO opens one Case for the same in-window cluster", ctx do
      batch = [
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

      assert_one_case_on_reingest(ctx, batch, "Split PO")
    end
  end

  describe "Conformance and Anomaly findings are idempotent across re-ingest" do
    test "a skipped-approval journey opens one Conformance Case", %{
      org: org,
      connection: connection
    } do
      batch = [
        %{
          type: :purchase_order,
          id: "PO5",
          quantity: 100,
          unit_price: 1_000_000,
          order_date: ~U[2026-03-01 09:00:00Z]
        },
        %{
          type: :goods_receipt,
          po_ref: "PO5",
          quantity: 100,
          occurred_at: ~U[2026-03-02 09:00:00Z]
        },
        %{
          type: :vendor_bill,
          po_ref: "PO5",
          quantity: 100,
          unit_price: 1_000_000,
          occurred_at: ~U[2026-03-03 09:00:00Z]
        },
        %{type: :payment, po_ref: "PO5", occurred_at: ~U[2026-03-04 09:00:00Z]}
      ]

      assert {:ok, _} = ingest(connection, batch, org)
      assert {:ok, _} = ingest(connection, batch, org)

      assert [case_record] = Compliance.list_cases!(tenant: org)
      case_record = Ash.load!(case_record, [:conformance_deviation], tenant: org)
      assert case_record.conformance_deviation.kind == :skipped_step
    end

    test "an unusually large payment opens one Anomaly Case", %{org: org, connection: connection} do
      history =
        for i <- 1..12 do
          %{
            type: :payment,
            vendor_id: "AV1",
            po_ref: "H#{i}",
            amount_total: 10_000_000,
            occurred_at: DateTime.add(~U[2025-01-01 09:00:00Z], i * 86_400, :second)
          }
        end

      assert {:ok, _} = Compliance.backfill_baselines(connection, history, tenant: org)

      big = [
        %{
          type: :payment,
          vendor_id: "AV1",
          po_ref: "PO-BIG",
          amount_total: 480_000_000,
          occurred_at: ~U[2026-03-01 09:00:00Z]
        }
      ]

      assert {:ok, _} = ingest(connection, big, org)
      assert {:ok, _} = ingest(connection, big, org)

      assert [case_record] = Compliance.list_cases!(tenant: org)
      case_record = Ash.load!(case_record, [:anomaly], tenant: org)
      assert case_record.anomaly.anomaly_type == :unusual_payment_amount
    end
  end

  defp assert_one_case_on_reingest(%{org: org, connection: connection}, batch, control_name) do
    assert {:ok, _} = ingest(connection, batch, org)
    assert {:ok, _} = ingest(connection, batch, org)

    assert [case_record] = Compliance.list_cases!(tenant: org)
    case_record = Ash.load!(case_record, [:violation], tenant: org)
    assert case_record.violation.control_name == control_name
  end
end
