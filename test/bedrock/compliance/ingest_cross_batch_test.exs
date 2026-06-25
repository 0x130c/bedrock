defmodule Bedrock.Compliance.IngestCrossBatchTest do
  @moduledoc """
  Domain-level coverage of cross-batch correlation (ADR-0011, Slice B / #25): under
  the v1 poller one P2P process is naturally split across many Ingest Batches, so
  detection must replay the Event History — feeding each *pure* detector the relevant
  recent history alongside the new batch — rather than correlating only within the
  single `ingest_events` call it is handed. Every scenario here splits one process
  across *separate* `ingest_events` calls and asserts on the resulting domain state
  (the Case/finding/evidence that opens), never on private functions. Closes #20, #21.
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

  # One vendor whose bank account changed, then was paid `window_hours` later — the
  # raw material for seeding the process-wide change→payment Baseline.
  defp change_then_pay(vendor_id, window_hours) do
    changed_at = ~U[2025-01-01 09:00:00Z]
    paid_at = DateTime.add(changed_at, window_hours * 3600, :second)

    [
      %{
        type: :vendor_change,
        vendor_id: vendor_id,
        field: :bank_account,
        old_value: "VN-#{vendor_id}-OLD",
        new_value: "VN-#{vendor_id}-NEW",
        occurred_at: changed_at
      },
      %{
        type: :payment,
        vendor_id: vendor_id,
        po_ref: "PO-#{vendor_id}",
        amount_total: 10_000_000,
        occurred_at: paid_at
      }
    ]
  end

  # A spread of normal change→payment windows (5–15 days) across distinct vendors.
  defp normal_history do
    [120, 168, 200, 240, 280, 300, 336, 360, 192, 264]
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {hours, i} -> change_then_pay("HV#{i}", hours) end)
  end

  describe "flagship anomaly across separate batches (#20)" do
    test "a vendor_change and the paying payment in separate ingest calls still open the bank-change→payment Anomaly Case with the before/after diff in Hard Evidence",
         %{org: org, connection: connection} do
      # Seed the process-wide Baseline of normal change→payment windows (5–15 days).
      assert {:ok, _} = Compliance.backfill_baselines(connection, normal_history(), tenant: org)

      # The bank account changes in one poll…
      change = [
        %{
          type: :vendor_change,
          vendor_id: "V1",
          field: :bank_account,
          old_value: "VN-OLD",
          new_value: "VN-NEW",
          occurred_at: ~U[2026-02-01 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, change, org)

      # …and the payment lands two hours later, in a *separate* poll. Single-batch
      # detection would never pair them; cross-batch replay must.
      payment = [
        %{
          type: :payment,
          id: "PAY1",
          vendor_id: "V1",
          po_ref: "PO-V1",
          amount_total: 50_000_000,
          occurred_at: ~U[2026-02-01 11:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, payment, org)

      case_record = Ash.load!(case_record, [:anomaly, :hard_evidence], tenant: org)
      assert case_record.anomaly.anomaly_type == :bank_change_before_payment

      diff = case_record.hard_evidence.snapshot["diff"]
      assert diff["before"] == "VN-OLD"
      assert diff["after"] == "VN-NEW"
    end
  end

  describe "Split-PO temporal evasion across separate batches (#21)" do
    test "same-vendor sub-threshold POs split across separate ingest calls are grouped and raise a Split PO Violation",
         %{org: org, connection: connection} do
      # PO-half-1 lands in one poll, under the 500M approval threshold on its own.
      half1 = [
        %{
          type: :purchase_order,
          id: "PO-A",
          vendor_id: "V9",
          amount_total: 300_000_000,
          currency: "VND",
          order_date: ~U[2026-02-01 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, half1, org)

      # PO-half-2 lands in a *separate* poll a day later, also under threshold alone —
      # but together they breach it. Single-batch detection never groups them.
      half2 = [
        %{
          type: :purchase_order,
          id: "PO-B",
          vendor_id: "V9",
          amount_total: 300_000_000,
          currency: "VND",
          order_date: ~U[2026-02-02 09:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, half2, org)

      case_record = Ash.load!(case_record, [:violation, :hard_evidence], tenant: org)
      assert case_record.violation.control_name == "Split PO"
      assert case_record.violation.reason =~ "PO-A"
      assert case_record.violation.reason =~ "PO-B"
    end
  end

  describe "conformance reconstruction across separate batches (#21)" do
    # The earlier sync: a PO approved, received and billed — a clean, in-flight
    # journey that opens no Case on its own.
    defp synced_journey_prefix do
      [
        %{
          type: :purchase_order,
          id: "PO-LATE",
          amount_total: 100_000_000,
          currency: "VND",
          order_date: ~U[2026-03-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        },
        %{
          type: :goods_receipt,
          id: "GR-LATE",
          po_ref: "PO-LATE",
          occurred_at: ~U[2026-03-02 09:00:00Z]
        },
        %{
          type: :vendor_bill,
          id: "VB-LATE",
          po_ref: "PO-LATE",
          occurred_at: ~U[2026-03-03 09:00:00Z]
        }
      ]
    end

    test "a batch carrying only a payment whose PO was synced earlier is conformance-checked, not dropped",
         %{org: org, connection: connection} do
      assert {:ok, []} = ingest(connection, synced_journey_prefix(), org)

      # A separate poll carries only the late payment. Single-batch reconstruction
      # filters to PO records and produces zero instances — the event is dropped and
      # never conformance-checked. Replay must attach it to the PO synced earlier.
      late_payment = [%{type: :payment, po_ref: "PO-LATE", occurred_at: ~U[2026-03-04 09:00:00Z]}]

      assert {:ok, []} = ingest(connection, late_payment, org)

      assert [instance] = Compliance.list_process_instances!(tenant: org)
      assert instance.po_ref == "PO-LATE"

      # The late payment joined the reconstructed journey (was checked, not dropped),
      # completing a conformant happy path — so no Case opened.
      assert "pay" in Enum.map(instance.activities, &Map.fetch!(&1, "activity"))
      assert [] = Compliance.list_cases!(tenant: org)
    end
  end

  describe "monotonic-safe conformance — omissions only at a terminal state" do
    test "an in-flight journey missing approval opens no omission Case, but the same omission opens once the PO is paid",
         %{org: org, connection: connection} do
      # An unapproved PO whose goods are received — an in-flight journey. The
      # approval may still arrive in a later poll (out-of-order is the norm under the
      # incremental poller), so an omission deviation here would be a false positive
      # that future appends could retract. None may open yet.
      in_flight = [
        %{
          type: :purchase_order,
          id: "PO-M",
          amount_total: 100_000_000,
          currency: "VND",
          order_date: ~U[2026-04-01 09:00:00Z]
        },
        %{
          type: :goods_receipt,
          id: "GR-M",
          po_ref: "PO-M",
          occurred_at: ~U[2026-04-02 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, in_flight, org)
      assert [] = Compliance.list_cases!(tenant: org)

      # The journey completes — billed then paid — without an approval ever arriving.
      # Now the Process Instance is terminal, the omission is stable under any future
      # append, and the skipped-approval Conformance Deviation must open.
      completion = [
        %{
          type: :vendor_bill,
          id: "VB-M",
          po_ref: "PO-M",
          occurred_at: ~U[2026-04-03 09:00:00Z]
        },
        %{type: :payment, po_ref: "PO-M", occurred_at: ~U[2026-04-04 09:00:00Z]}
      ]

      assert {:ok, [case_record]} = ingest(connection, completion, org)

      case_record = Ash.load!(case_record, [:conformance_deviation], tenant: org)
      assert case_record.conformance_deviation.kind == :skipped_step
      assert case_record.conformance_deviation.reason =~ "approval"
    end
  end

  describe "conformance false positive across separate batches (#21)" do
    test "a batch carrying goods_receipt whose approval was synced in an earlier batch opens no false :skipped_step Case",
         %{org: org, connection: connection} do
      # The approval is captured in an earlier poll, as part of the PO snapshot.
      approved_po = [
        %{
          type: :purchase_order,
          id: "PO-FP",
          amount_total: 100_000_000,
          currency: "VND",
          order_date: ~U[2026-05-01 09:00:00Z],
          approvals: [%{role: "CFO"}]
        }
      ]

      assert {:ok, []} = ingest(connection, approved_po, org)

      # A later poll carries only the goods receipt. Single-batch reconstruction
      # would either drop it (no PO anchor) or, seeing it alone, flag a skipped
      # approval — a false positive, since the PO was legitimately approved earlier.
      goods_receipt = [
        %{type: :goods_receipt, po_ref: "PO-FP", occurred_at: ~U[2026-05-02 09:00:00Z]}
      ]

      assert {:ok, []} = ingest(connection, goods_receipt, org)

      # No Case at all — and the receipt was attached to the earlier-synced, approved
      # journey (checked, not dropped), which conforms so far.
      assert [] = Compliance.list_cases!(tenant: org)
      assert [instance] = Compliance.list_process_instances!(tenant: org)

      assert Enum.map(instance.activities, &Map.fetch!(&1, "activity")) == [
               "approve",
               "receive_goods"
             ]
    end
  end

  describe "idempotency under cross-batch replay (ADR-0011)" do
    test "re-ingesting a split-PO sequence (poll overlap) opens no second Case and no second journey",
         %{org: org, connection: connection} do
      half1 = [
        %{
          type: :purchase_order,
          id: "PO-A",
          vendor_id: "V9",
          amount_total: 300_000_000,
          currency: "VND",
          order_date: ~U[2026-02-01 09:00:00Z]
        }
      ]

      half2 = [
        %{
          type: :purchase_order,
          id: "PO-B",
          vendor_id: "V9",
          amount_total: 300_000_000,
          currency: "VND",
          order_date: ~U[2026-02-02 09:00:00Z]
        }
      ]

      # The real sequence: two polls. The second pairs with the replayed first and
      # opens the Split PO Case.
      assert {:ok, []} = ingest(connection, half1, org)
      assert {:ok, [_case]} = ingest(connection, half2, org)

      # A poll overlap re-delivers both halves. Replay now finds each half in the
      # Event History too, but the Episode-grained finding_key keeps it a no-op.
      assert {:ok, _} = ingest(connection, half1, org)
      assert {:ok, _} = ingest(connection, half2, org)

      assert [case_record] = Compliance.list_cases!(tenant: org)
      case_record = Ash.load!(case_record, [:violation], tenant: org)
      assert case_record.violation.control_name == "Split PO"

      # The two POs project to exactly two `{po_ref}` journeys, never appended-to.
      assert length(Compliance.list_process_instances!(tenant: org)) == 2
    end
  end

  describe "vendor-bank change detected poll-only via snapshot-diff (#20, AC#6)" do
    test "a changed res.partner.bank snapshot synthesizes a vendor_change that pairs with a later payment — no webhook, no Odoo install",
         %{org: org, connection: connection} do
      assert {:ok, _} = Compliance.backfill_baselines(connection, normal_history(), tenant: org)

      # First poll: the vendor's bank account as it stands. Nothing to diff against
      # yet, so no change is synthesized and nothing fires.
      assert {:ok, []} =
               ingest(
                 connection,
                 [
                   %{
                     type: :vendor_bank,
                     id: "BANK1",
                     vendor_id: "V1",
                     acc_number: "VN-OLD",
                     write_date: ~U[2026-02-01 08:00:00Z]
                   }
                 ],
                 org
               )

      # A later poll sees the same bank record with a *different* account number.
      # The seam diffs it against the last-known snapshot and synthesizes a
      # bank-account vendor_change — purely from polling, no webhook.
      assert {:ok, []} =
               ingest(
                 connection,
                 [
                   %{
                     type: :vendor_bank,
                     id: "BANK1",
                     vendor_id: "V1",
                     acc_number: "VN-NEW",
                     write_date: ~U[2026-02-02 09:00:00Z]
                   }
                 ],
                 org
               )

      # The payment follows two hours after the synthesized change, in yet another
      # poll. Cross-batch replay pairs it with the synthesized change and the
      # flagship Anomaly opens, carrying the polled before/after diff.
      payment = [
        %{
          type: :payment,
          id: "PAY1",
          vendor_id: "V1",
          po_ref: "PO-V1",
          amount_total: 50_000_000,
          occurred_at: ~U[2026-02-02 11:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, payment, org)

      case_record = Ash.load!(case_record, [:anomaly, :hard_evidence], tenant: org)
      assert case_record.anomaly.anomaly_type == :bank_change_before_payment

      diff = case_record.hard_evidence.snapshot["diff"]
      assert diff["before"] == "VN-OLD"
      assert diff["after"] == "VN-NEW"
    end
  end
end
