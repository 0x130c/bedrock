defmodule Bedrock.Compliance.Event do
  @moduledoc """
  A normalized P2P fact in the tenant-scoped **Event History** (ADR-0011) — the
  retained corpus Bedrock keeps independent of Odoo, the substrate for cross-batch
  correlation and Process Instance reconstruction (read side is Slice B). Distinct
  from the Evidence Ledger (verdict-bearing Hard Evidence) and from Odoo's own
  audit log.

  Each Event is **upserted-latest** by the *semantic* natural key the normalizer
  assigns — `{model, odoo_id}` for entities and discrete facts, `{vendor_id, field,
  occurred_at}` for change facts — **never** the source-row id, so the same
  real-world fact arriving via poll and via webhook deduplicates to one Event
  (ADR-0003). Re-emitting it (poll overlap, Oban retry, webhook-then-poll) is a
  no-op or an in-place refresh, never a duplicate. No version history in v1.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "events"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      # Upsert-latest by the semantic key: re-emitting the same fact refreshes the
      # payload in place rather than appending a second Event.
      upsert? true
      upsert_identity :unique_natural_key
      upsert_fields [:event_type, :payload, :occurred_at]
      accept [:natural_key, :event_type, :payload, :occurred_at]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The semantic natural key the normalizer assigned — the dedup identity.
    attribute :natural_key, :string do
      allow_nil? false
      public? true
    end

    # The kind of P2P fact (`purchase_order`, `vendor`, `vendor_change`, …).
    attribute :event_type, :string do
      allow_nil? false
      public? true
    end

    # The normalized record exactly as the detectors read it.
    attribute :payload, :map do
      allow_nil? false
      public? true
    end

    # When the fact occurred, when known — the spine of cross-batch correlation.
    attribute :occurred_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_natural_key, [:natural_key]
  end
end
