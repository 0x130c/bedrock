defmodule Bedrock.Compliance.Attestation do
  @moduledoc """
  The Auditor's recorded, identity-bound approval of a `Case` decision (ADR-0009) —
  an *internal* assertion that a human reviewed the Hard Evidence and decided. Bound
  to the Auditor's identity by `auditor_id` (the acting `User`) and stamped with
  `attested_at`. Explicitly NOT a chữ ký số (Digital Signature): no public-CA
  certificate, no statutory e-signature weight.

  Recorded as part of closing a Case and later bundled into the exported Audit Report.
  Tenant-scoped; belongs to the `Case`. The `User` lives in the public `Accounts`
  schema, so identity is captured by value (`auditor_id` / `auditor_email`), not a
  cross-schema foreign key.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "attestations"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:auditor_id, :auditor_email]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The acting Auditor's identity, captured by value from the actor.
    attribute :auditor_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :auditor_email, :string do
      allow_nil? false
      public? true
    end

    attribute :attested_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :case, Bedrock.Compliance.Case do
      allow_nil? false
    end
  end
end
