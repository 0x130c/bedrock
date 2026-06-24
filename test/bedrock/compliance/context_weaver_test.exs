defmodule Bedrock.Compliance.ContextWeaverTest do
  @moduledoc """
  Layer 3 — the Context Weaver. After `ingest_events` opens a `Case`, an
  `AINarrative` is woven asynchronously (Oban) from the Case's Hard Evidence.
  The narrative is machine-generated context, never a verdict, and its failure
  never blocks or alters the Case verdict.
  """
  use Bedrock.DataCase, async: false

  import ExUnit.CaptureLog

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

  defp breaching_po do
    %{
      id: "PO0042",
      amount_total: 750_000_000,
      currency: "VND",
      approvals: [%{role: "manager"}]
    }
  end

  # A PO journey that skips approval — opens a single Conformance Deviation Case
  # (no Rule Violation), so the weave queue holds exactly one job.
  defp skipped_approval_journey do
    [
      %{
        type: :purchase_order,
        id: "PO5",
        amount_total: 100_000_000,
        currency: "VND",
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
  end

  describe "weaving an AINarrative on a Case" do
    test "a Case yields an AINarrative linked to it once the weave job runs",
         %{org: org, connection: connection} do
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, [breaching_po()], tenant: org)

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative], tenant: org)

      assert case_record.ai_narrative
      assert is_binary(case_record.ai_narrative.summary)
      assert case_record.ai_narrative.summary != ""
    end

    test "the narrative is plainly machine-generated and leaves the Hard Evidence untouched",
         %{org: org, connection: connection} do
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, [breaching_po()], tenant: org)

      assert %{success: 1} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative, :hard_evidence], tenant: org)

      # Plainly labeled as machine-generated context.
      assert case_record.ai_narrative.machine_generated == true

      # A distinct record, separate from and subordinate to the Hard Evidence:
      # weaving never overwrites or replaces the verdict-bearing facts.
      assert case_record.ai_narrative.id != case_record.hard_evidence.id
      assert case_record.hard_evidence.snapshot["id"] == "PO0042"
      assert case_record.hard_evidence.snapshot["amount_total"] == 750_000_000
    end

    test "the narrative is woven from the Case's Hard Evidence", %{
      org: org,
      connection: connection
    } do
      # Echo mode: the fake LLM reflects the prompt it received, so a narrative
      # that mentions the PO proves the Hard Evidence reached the Context Weaver.
      Application.put_env(:bedrock, :context_weaver_stub, :echo)
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, [breaching_po()], tenant: org)

      assert %{success: 1} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative], tenant: org)

      assert case_record.ai_narrative.summary =~ "PO0042"
      assert case_record.ai_narrative.summary =~ "Threshold Approval"
    end
  end

  describe "weaving an AINarrative on a Conformance Deviation Case" do
    test "a Conformance Deviation Case also yields an AINarrative once the weave job runs",
         %{org: org, connection: connection} do
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, skipped_approval_journey(), tenant: org)

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative, :conformance_deviation], tenant: org)

      assert case_record.conformance_deviation.kind == :skipped_step
      assert case_record.ai_narrative
      assert is_binary(case_record.ai_narrative.summary)
      assert case_record.ai_narrative.summary != ""
    end

    test "the conformance narrative is woven from the journey Hard Evidence", %{
      org: org,
      connection: connection
    } do
      Application.put_env(:bedrock, :context_weaver_stub, :echo)
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, skipped_approval_journey(), tenant: org)

      assert %{success: 1} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative], tenant: org)

      # The PO ref proves the journey snapshot reached the weaver; the control
      # label identifies the finding as a conformance check, not a rule breach.
      assert case_record.ai_narrative.summary =~ "PO5"
      assert case_record.ai_narrative.summary =~ "Conformance"
    end
  end

  # A process-wide Baseline of normal change→payment windows (5–15 days), then one
  # vendor paid just 2h after its bank account changed — a flagship Layer-2 Anomaly.
  defp bank_change_history do
    [120, 168, 216, 264, 312, 360]
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {hours, i} ->
      changed = ~U[2025-01-01 09:00:00Z]

      [
        %{
          type: :vendor_change,
          vendor_id: "H#{i}",
          field: :bank_account,
          old_value: "A#{i}",
          new_value: "B#{i}",
          occurred_at: changed
        },
        %{
          type: :payment,
          vendor_id: "H#{i}",
          po_ref: "P#{i}",
          amount_total: 10_000_000,
          occurred_at: DateTime.add(changed, hours * 3600, :second)
        }
      ]
    end)
  end

  defp fast_redirect_payment do
    [
      %{
        type: :vendor_change,
        vendor_id: "VX",
        field: :bank_account,
        old_value: "VN-LEGIT",
        new_value: "VN-EVIL",
        occurred_at: ~U[2026-02-01 09:00:00Z]
      },
      %{
        type: :payment,
        vendor_id: "VX",
        po_ref: "PO-X",
        amount_total: 50_000_000,
        occurred_at: ~U[2026-02-01 11:00:00Z]
      }
    ]
  end

  describe "weaving an AINarrative on an Anomaly Case" do
    test "an Anomaly Case also yields an AINarrative once the weave job runs",
         %{org: org, connection: connection} do
      assert {:ok, _} =
               Compliance.backfill_baselines(connection, bank_change_history(), tenant: org)

      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, fast_redirect_payment(), tenant: org)

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative, :anomaly], tenant: org)

      assert case_record.anomaly.anomaly_type == :bank_change_before_payment
      assert case_record.ai_narrative
      assert is_binary(case_record.ai_narrative.summary)
      assert case_record.ai_narrative.summary != ""
    end

    test "the anomaly narrative is woven from the candidate's Hard Evidence", %{
      org: org,
      connection: connection
    } do
      Application.put_env(:bedrock, :context_weaver_stub, :echo)
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      assert {:ok, _} =
               Compliance.backfill_baselines(connection, bank_change_history(), tenant: org)

      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, fast_redirect_payment(), tenant: org)

      assert %{success: 1} = Oban.drain_queue(queue: :weave_narrative)

      case_record = Ash.load!(case_record, [:ai_narrative], tenant: org)

      # The control label marks this as a Layer-2 Anomaly candidate, not a verdict.
      assert case_record.ai_narrative.summary =~ "Anomaly"
    end
  end

  describe "graceful degradation when the Context Weaver fails" do
    test "a failed weave leaves the Case verdict — Violation and Hard Evidence — fully intact",
         %{org: org, connection: connection} do
      Application.put_env(:bedrock, :context_weaver_stub, {:error, :llm_unavailable})
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      # The verdict is committed regardless of Layer 3: ingestion still succeeds.
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, [breaching_po()], tenant: org)

      # The weave job does not succeed — but only the job is affected, and the
      # failure is surfaced (logged), never swallowed silently.
      log =
        capture_log(fn ->
          assert %{success: 0} = Oban.drain_queue(queue: :weave_narrative)
        end)

      assert log =~ "weave_narrative"

      case_record =
        Ash.load!(case_record, [:violation, :hard_evidence, :ai_narrative], tenant: org)

      # No narrative, and the Case is not marked as woven.
      refute case_record.ai_narrative
      refute case_record.narrative_woven_at

      # The verdict-bearing facts are untouched.
      assert case_record.violation.control_name == "Threshold Approval"
      assert case_record.hard_evidence.snapshot["id"] == "PO0042"

      # The Case itself survives and is still listable.
      assert [_one] = Compliance.list_cases!(tenant: org)
    end

    test "a failed weave leaves a Conformance Deviation Case verdict — deviation and Hard Evidence — fully intact",
         %{org: org, connection: connection} do
      Application.put_env(:bedrock, :context_weaver_stub, {:error, :llm_unavailable})
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      # The verdict is committed regardless of Layer 3: ingestion still succeeds.
      assert {:ok, [case_record]} =
               Compliance.ingest_events(connection, skipped_approval_journey(), tenant: org)

      # Only the weave job is affected, and the failure is surfaced (logged).
      log =
        capture_log(fn ->
          assert %{success: 0} = Oban.drain_queue(queue: :weave_narrative)
        end)

      assert log =~ "weave_narrative"

      case_record =
        Ash.load!(case_record, [:conformance_deviation, :hard_evidence, :ai_narrative],
          tenant: org
        )

      # No narrative, and the Case is not marked as woven.
      refute case_record.ai_narrative
      refute case_record.narrative_woven_at

      # The verdict-bearing facts are untouched.
      assert case_record.conformance_deviation.kind == :skipped_step
      assert case_record.hard_evidence.snapshot["po_ref"] == "PO5"

      # The Case itself survives and is still listable.
      assert [_one] = Compliance.list_cases!(tenant: org)
    end
  end

  describe "weaving a Case that carries no typed finding" do
    test "weaves from Hard Evidence instead of crashing", %{org: org} do
      Application.put_env(:bedrock, :context_weaver_stub, :echo)
      on_exit(fn -> Application.delete_env(:bedrock, :context_weaver_stub) end)

      # A Case with Hard Evidence but no Violation / ConformanceDeviation / Anomaly — a
      # shape a future Case-open path could produce. Seeded directly to bypass the
      # finding-required open actions. Weaving must degrade gracefully, not crash.
      case_record =
        Ash.Seed.seed!(Compliance.Case, %{title: "Bare case", status: :open}, tenant: org)

      Ash.Seed.seed!(
        Compliance.HardEvidence,
        %{snapshot: %{"note" => "evidence without a typed finding"}, case_id: case_record.id},
        tenant: org
      )

      case_record =
        case_record
        |> Ash.Changeset.for_update(:weave_narrative, %{}, tenant: org)
        |> Ash.update!()

      case_record = Ash.load!(case_record, [:ai_narrative], tenant: org)

      assert case_record.ai_narrative
      assert is_binary(case_record.ai_narrative.summary)
      assert case_record.ai_narrative.summary != ""
    end
  end
end
