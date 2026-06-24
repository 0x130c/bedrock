defmodule Bedrock.Compliance.Baseline do
  @moduledoc """
  The learned "normal" of one behaviour — the distribution the Layer-2 Anomaly
  Detection Engine measures deviation against (CONTEXT.md). Keyed by the entity it
  describes (`{entity_type, entity_ref}`) and the `metric` it summarizes
  (e.g. a process-wide change→payment window, a vendor's payment amount).

  Computed by the backfill bootstrap from a batch of historical events (ADR-0006):
  it stores the sample `count`, `mean`, `stddev` and the sorted `samples` so
  `Bedrock.Compliance.AnomalyDetection.score/2` can read an exact empirical
  percentile. Tenant-scoped (ADR-0007); re-backfilling upserts on its natural key.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "baselines"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_baseline
      accept [:entity_type, :entity_ref, :metric, :count, :mean, :stddev, :samples]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The entity this Baseline describes — a vendor, a user, or the process itself.
    attribute :entity_type, :atom do
      constraints one_of: [:vendor, :process, :user]
      allow_nil? false
      public? true
    end

    # The concrete entity (a vendor id, or "p2p" for the process-wide Baseline).
    attribute :entity_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :metric, :atom do
      constraints one_of: [:bank_change_to_payment_hours, :payment_amount]
      allow_nil? false
      public? true
    end

    attribute :count, :integer do
      allow_nil? false
      public? true
    end

    attribute :mean, :float do
      allow_nil? false
      public? true
    end

    attribute :stddev, :float do
      allow_nil? false
      public? true
    end

    # The sorted historical samples, so scoring can read an exact percentile.
    attribute :samples, {:array, :float} do
      allow_nil? false
      default []
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_baseline, [:entity_type, :entity_ref, :metric]
  end
end
