defmodule Bedrock.Compliance.Anomaly do
  @moduledoc """
  A behavioural outlier raised by the Layer-2 Anomaly Detection Engine, carrying an
  `Anomaly Score` (0–100). A *candidate* for human review — explicitly NOT a
  `Violation` and never a verdict (CONTEXT.md). The third finding type that can
  open a `Case`, sibling to a `Violation` and a `ConformanceDeviation`.

  Names the kind of outlier, the entity under suspicion, and a human-readable
  reason framed as a candidate. Tenant-scoped; belongs to the `Case` it opened.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "anomalies"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:anomaly_type, :score, :reason, :entity_ref]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :anomaly_type, :atom do
      constraints one_of: [:bank_change_before_payment, :unusual_payment_amount]
      allow_nil? false
      public? true
    end

    # The Anomaly Score: how unusual the behavior is relative to its Baseline.
    # Suspicion, not a verdict.
    attribute :score, :integer do
      constraints min: 0, max: 100
      allow_nil? false
      public? true
    end

    attribute :reason, :string do
      allow_nil? false
      public? true
    end

    # The entity under suspicion (e.g. the vendor id) — the subject of the Case.
    attribute :entity_ref, :string do
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
