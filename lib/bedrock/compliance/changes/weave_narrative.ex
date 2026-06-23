defmodule Bedrock.Compliance.Changes.WeaveNarrative do
  @moduledoc """
  Weaves an `AINarrative` for a `Case` from its Hard Evidence via the Context
  Weaver (Layer 3) and links it to the Case. Runs inside the async weave job, so
  any LLM failure fails only the job — the already-committed Case verdict is
  untouched.
  """
  use Ash.Resource.Change

  alias Bedrock.Compliance
  alias Bedrock.Compliance.ContextWeaver

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case_record =
        Ash.load!(changeset.data, [:violation, :hard_evidence], tenant: changeset.tenant)

      model = ContextWeaver.model()

      summary =
        Compliance.summarize!(
          case_record.violation.control_name,
          case_record.violation.reason,
          case_record.hard_evidence.snapshot
        )

      changeset
      |> Ash.Changeset.force_change_attribute(:narrative_woven_at, DateTime.utc_now())
      |> Ash.Changeset.manage_relationship(
        :ai_narrative,
        %{summary: summary, model: model},
        type: :create
      )
    end)
  end
end
