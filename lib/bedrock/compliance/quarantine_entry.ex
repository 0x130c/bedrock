defmodule Bedrock.Compliance.QuarantineEntry do
  @moduledoc """
  A record the normalizer rejected at the ingestion seam because it failed the
  pinned field contract (ADR-0011) — e.g. an `amount_total` that is not an integer
  (minor units) or `Money`. Persisting it, rather than dropping it silently or
  letting it crash the batch, makes the data-quality breach a **visible, queryable
  signal** an Auditor can act on while the rest of the Ingest Batch proceeds.
  Tenant-scoped (ADR-0007).
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "quarantine_entries"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:raw, :reason]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The original, un-coerced record exactly as it arrived — evidence of what was
    # rejected, so a human can re-feed it once the upstream defect is fixed.
    attribute :raw, :map do
      allow_nil? false
      public? true
    end

    # Why it failed the contract, naming the offending field.
    attribute :reason, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end
end
