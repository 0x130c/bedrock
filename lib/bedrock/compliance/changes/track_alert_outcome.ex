defmodule Bedrock.Compliance.Changes.TrackAlertOutcome do
  @moduledoc """
  Tallies an Alert's outcome as its Case is resolved (ADR-0010). Only Cases that
  actually alerted feed per-Control precision: a confirmed or accepted-risk Case is
  an *actioned* Alert, a dismissed one counts against precision. Cases that never
  alerted are ignored. Runs after the resolution commits, in the same tenant.
  """
  use Ash.Resource.Change

  alias Bedrock.Compliance.AlertPrecision

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, case_record ->
      case_record = Ash.load!(case_record, [:alert], tenant: context.tenant)

      if case_record.alert do
        actioned? = case_record.status in [:confirmed, :accepted_risk]
        AlertPrecision.record_outcome(case_record.finding_type, actioned?, context.tenant)
      end

      {:ok, case_record}
    end)
  end
end
