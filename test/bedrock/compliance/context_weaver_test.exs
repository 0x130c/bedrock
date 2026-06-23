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
  end
end
