defmodule Bedrock.Compliance.Case do
  @moduledoc """
  The investigation record a human Auditor works on. Opened by a finding and
  bundles the `Violation` with the `HardEvidence` behind it. Tenant-scoped.

  In Slice 1 a Case is opened by exactly one `Violation` and carries one
  `HardEvidence` snapshot; richer lifecycle (status transitions, attestation)
  arrives in later slices.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cases"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :open do
      description "Open a Case, creating its Violation and HardEvidence in one transaction."
      accept [:title]

      argument :violation, :map, allow_nil?: false
      argument :hard_evidence, :map, allow_nil?: false

      change manage_relationship(:violation, type: :create)
      change manage_relationship(:hard_evidence, type: :create)
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:open, :resolved, :dismissed]
      default :open
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    has_one :violation, Bedrock.Compliance.Violation
    has_one :hard_evidence, Bedrock.Compliance.HardEvidence
  end
end
