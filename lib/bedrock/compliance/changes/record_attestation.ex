defmodule Bedrock.Compliance.Changes.RecordAttestation do
  @moduledoc """
  Records the Auditor's `Attestation` as a `Case` is closed (ADR-0009). The
  Attestation is identity-bound: it captures the acting `User`'s id and email from
  the actor. Closing without an actor is rejected — a Case can never be closed
  without an attributable human standing behind the decision.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: nil}) do
    Ash.Changeset.add_error(changeset,
      field: :attestation,
      message: "an Attestation by an authenticated Auditor is required to close a Case"
    )
  end

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.manage_relationship(
      changeset,
      :attestation,
      %{auditor_id: actor.id, auditor_email: to_string(actor.email)},
      type: :create
    )
  end
end
