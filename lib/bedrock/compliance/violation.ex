defmodule Bedrock.Compliance.Violation do
  @moduledoc """
  A confirmed deterministic breach of a Compliance Rule, produced by the Layer-1
  Deterministic Engine. Names the Control it breached and carries a
  human-readable reason. Tenant-scoped; belongs to the `Case` it opened.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "violations"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:control_name, :reason]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :control_name, :string do
      allow_nil? false
      public? true
    end

    attribute :reason, :string do
      allow_nil? false
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
