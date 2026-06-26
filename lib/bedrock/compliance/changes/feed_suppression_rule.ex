defmodule Bedrock.Compliance.Changes.FeedSuppressionRule do
  @moduledoc """
  Feeds a `SuppressionRule` from a Case dismissed as known-good (ADR-0010). When the
  Auditor dismisses with `suppress?: true`, the Case's `{finding_type, subject}` and
  its dismissal reason become a rule, so matching findings stop promoting to Alerts
  while still opening Cases. Ordinary dismissals leave the precision channel untouched.

  Runs after the dismissal commits, in the same tenant; the rule upserts on its
  pattern, so dismissing twice is idempotent.
  """
  use Ash.Resource.Change

  alias Bedrock.Compliance

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, case_record ->
      if suppress?(changeset) and suppressible?(case_record) do
        Compliance.create_suppression_rule!(
          %{
            control_name: case_record.finding_type,
            subject: case_record.subject,
            reason: case_record.dismissal_reason
          },
          tenant: context.tenant
        )
      end

      {:ok, case_record}
    end)
  end

  defp suppress?(changeset), do: Ash.Changeset.get_argument(changeset, :suppress?) == true

  # A rule needs both halves of its pattern; a finding source without a subject or
  # type cannot seed one.
  defp suppressible?(%{finding_type: type, subject: subject}),
    do: is_binary(type) and is_binary(subject)
end
