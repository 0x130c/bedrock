defmodule Bedrock.Compliance.ConformanceDeviation do
  @moduledoc """
  A deterministic divergence of a `ProcessInstance` from the expected `Process` —
  the "flow" half of process compliance and a Layer-1 finding, sibling to a
  `Violation` (ADR-0004). Names the kind of divergence and carries a
  human-readable reason. Tenant-scoped; belongs to the `Case` it opened.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conformance_deviations"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:kind, :reason, :po_ref]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom do
      constraints one_of: [:skipped_step, :out_of_order, :receive_after_pay]
      allow_nil? false
      public? true
    end

    attribute :reason, :string do
      allow_nil? false
      public? true
    end

    # The Purchase Order whose journey diverged — the subject of the Case.
    attribute :po_ref, :string do
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
