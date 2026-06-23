defmodule Bedrock.Compliance.IngestConformanceTest do
  @moduledoc """
  Domain-level coverage of P2P conformance, driven through the single
  `ingest_events` seam with fixture event sequences (no real Odoo). Asserts on
  resulting domain state — the `ProcessInstance` reconstructed per PO and the
  `Case`/`ConformanceDeviation`/`HardEvidence` a deviation opens — never on
  private functions.
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

  describe "Process Instance reconstruction" do
    test "ingest reconstructs one ordered Process Instance per PO from its events", %{
      org: org,
      connection: connection
    } do
      records = [
        %{type: :payment, po_ref: "PO1", occurred_at: ~U[2026-02-04 09:00:00Z]},
        %{
          type: :purchase_order,
          id: "PO1",
          amount_total: 100_000_000,
          currency: "VND",
          order_date: ~U[2026-02-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{type: :vendor_bill, po_ref: "PO1", occurred_at: ~U[2026-02-03 09:00:00Z]},
        %{type: :goods_receipt, po_ref: "PO1", occurred_at: ~U[2026-02-02 09:00:00Z]}
      ]

      assert {:ok, _cases} = ingest(connection, records, org)

      assert [instance] = Compliance.list_process_instances!(tenant: org)
      assert instance.po_ref == "PO1"

      assert Enum.map(instance.activities, &Map.fetch!(&1, "activity")) ==
               ["approve", "receive_goods", "bill", "pay"]
    end
  end

  describe "Conformance Deviation opens a Case" do
    test "a PO that skips approval opens a Case with the deviation and the journey as Hard Evidence",
         %{org: org, connection: connection} do
      records = [
        %{
          type: :purchase_order,
          id: "PO5",
          amount_total: 100_000_000,
          currency: "VND",
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

      assert {:ok, [case_record]} = ingest(connection, records, org)

      case_record = Ash.load!(case_record, [:conformance_deviation, :hard_evidence], tenant: org)

      assert case_record.conformance_deviation.kind == :skipped_step
      assert case_record.conformance_deviation.reason =~ "approval"
      assert case_record.hard_evidence.snapshot["po_ref"] == "PO5"

      journey =
        case_record.hard_evidence.snapshot["journey"] |> Enum.map(&Map.fetch!(&1, "activity"))

      assert journey == ["receive_goods", "bill", "pay"]
    end

    test "a goods receipt timestamped after payment opens a receive-after-pay Case", %{
      org: org,
      connection: connection
    } do
      records = [
        %{
          type: :purchase_order,
          id: "PO6",
          amount_total: 100_000_000,
          currency: "VND",
          unit_price: 1_000_000,
          order_date: ~U[2026-05-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{
          type: :goods_receipt,
          po_ref: "PO6",
          quantity: 60,
          occurred_at: ~U[2026-05-02 09:00:00Z]
        },
        %{
          type: :vendor_bill,
          po_ref: "PO6",
          quantity: 100,
          unit_price: 1_000_000,
          occurred_at: ~U[2026-05-03 09:00:00Z]
        },
        %{type: :payment, po_ref: "PO6", occurred_at: ~U[2026-05-04 09:00:00Z]},
        # A corrective receipt logged only after the PO was already paid.
        %{
          type: :goods_receipt,
          po_ref: "PO6",
          quantity: 40,
          occurred_at: ~U[2026-05-05 09:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, records, org)

      case_record = Ash.load!(case_record, [:conformance_deviation], tenant: org)
      assert case_record.conformance_deviation.kind == :receive_after_pay
    end

    test "a duplicate payment recorded after the PO is paid opens an out-of-order Case", %{
      org: org,
      connection: connection
    } do
      records = [
        %{
          type: :purchase_order,
          id: "PO8",
          amount_total: 100_000_000,
          currency: "VND",
          unit_price: 1_000_000,
          order_date: ~U[2026-06-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{
          type: :goods_receipt,
          po_ref: "PO8",
          quantity: 100,
          occurred_at: ~U[2026-06-02 09:00:00Z]
        },
        %{
          type: :vendor_bill,
          po_ref: "PO8",
          quantity: 100,
          unit_price: 1_000_000,
          occurred_at: ~U[2026-06-03 09:00:00Z]
        },
        %{type: :payment, po_ref: "PO8", occurred_at: ~U[2026-06-04 09:00:00Z]},
        %{type: :payment, po_ref: "PO8", occurred_at: ~U[2026-06-05 09:00:00Z]}
      ]

      assert {:ok, [case_record]} = ingest(connection, records, org)

      case_record = Ash.load!(case_record, [:conformance_deviation], tenant: org)
      assert case_record.conformance_deviation.kind == :out_of_order
    end
  end

  describe "clean conformant journey" do
    test "a full happy-path PO journey reconstructs an instance but opens no Case", %{
      org: org,
      connection: connection
    } do
      records = [
        %{
          type: :purchase_order,
          id: "PO7",
          amount_total: 100_000_000,
          currency: "VND",
          quantity: 100,
          unit_price: 1_000_000,
          order_date: ~U[2026-04-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{
          type: :goods_receipt,
          po_ref: "PO7",
          quantity: 100,
          occurred_at: ~U[2026-04-02 09:00:00Z]
        },
        %{
          type: :vendor_bill,
          po_ref: "PO7",
          quantity: 100,
          unit_price: 1_000_000,
          occurred_at: ~U[2026-04-03 09:00:00Z]
        },
        %{type: :payment, po_ref: "PO7", occurred_at: ~U[2026-04-04 09:00:00Z]}
      ]

      assert {:ok, []} = ingest(connection, records, org)
      assert [] = Compliance.list_cases!(tenant: org)
      assert [_instance] = Compliance.list_process_instances!(tenant: org)
    end
  end
end
