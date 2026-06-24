defmodule Bedrock.Compliance.Changes.WeaveNarrative do
  @moduledoc """
  Weaves an `AINarrative` for a `Case` from its Hard Evidence via the Context
  Weaver (Layer 3) and links it to the Case. Runs inside the async weave job, so
  any LLM failure fails only the job — the already-committed Case verdict is
  untouched.

  Works for any of the three findings that can open a Case (ADR-0004): a Rule
  `Violation` names its Control, a `ConformanceDeviation` is weaved under the P2P
  Conformance check, and a Layer-2 `Anomaly` is weaved as a candidate (never a
  verdict) — each with its deterministic reason as context.
  """
  use Ash.Resource.Change

  alias Bedrock.Compliance
  alias Bedrock.Compliance.ContextWeaver

  @conformance_control_name "P2P Conformance"
  @anomaly_control_name "Anomaly Detection (Layer 2)"

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case_record =
        Ash.load!(
          changeset.data,
          [:violation, :conformance_deviation, :anomaly, :hard_evidence],
          tenant: changeset.tenant
        )

      {control_name, reason} = finding(case_record)
      model = ContextWeaver.model()

      summary =
        Compliance.summarize!(control_name, reason, case_record.hard_evidence.snapshot)

      changeset
      |> Ash.Changeset.force_change_attribute(:narrative_woven_at, DateTime.utc_now())
      |> Ash.Changeset.manage_relationship(
        :ai_narrative,
        %{summary: summary, model: model},
        type: :create
      )
    end)
  end

  # The Control name and deterministic reason that frame the narrative, taken from
  # whichever finding opened the Case.
  defp finding(%{violation: %{control_name: control_name, reason: reason}}),
    do: {control_name, reason}

  defp finding(%{conformance_deviation: %{reason: reason}}),
    do: {@conformance_control_name, reason}

  defp finding(%{anomaly: %{reason: reason}}),
    do: {@anomaly_control_name, reason}
end
