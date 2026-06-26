defmodule Bedrock.Compliance.Alert do
  @moduledoc """
  The precision channel (ADR-0010): a low-latency outbound signal Bedrock emits
  only when a finding clears the promotion gate. An Alert *points at* a `Case` — it
  is not the Case itself — and is delivered via a swappable port (Slack / Telegram /
  SMS / webhook). Tenant-scoped; at most one Alert per Case.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "alerts"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :promote do
      description "Promote a gated finding's Case into an Alert (the precision channel)."
      primary? true
      accept [:case_id, :severity, :anomaly_score, :money_at_risk, :channel]
    end

    update :mark_delivered do
      description "Record that this Alert was delivered over its channel."
      require_atomic? false

      change set_attribute(:delivery_status, :delivered)

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :delivered_at, DateTime.utc_now())
      end
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The deterministic Severity band that promoted a Violation (ADR-0010). Nil for a
    # pure Anomaly, whose signal is its Anomaly Score, not a deterministic Severity.
    attribute :severity, :atom do
      constraints one_of: [:low, :medium, :high, :critical]
      public? true
    end

    # The Anomaly Score that promoted a Layer-2 candidate. Nil for a Violation.
    attribute :anomaly_score, :integer do
      constraints min: 0, max: 100
      public? true
    end

    # The money-at-risk that cleared the Materiality Floor.
    attribute :money_at_risk, :money do
      public? true
    end

    # The transport this Alert is delivered over (ADR-0002). Defaults to a generic
    # webhook; per-Organization channel selection arrives in a later slice.
    attribute :channel, :atom do
      constraints one_of: [:slack, :telegram, :sms, :webhook]
      allow_nil? false
      default :webhook
      public? true
    end

    # Delivery state through the port. `:pending` until the adapter confirms, then
    # `:delivered`; a failed attempt leaves it `:pending` (the recall channel already
    # holds the Case, so delivery never blocks the verdict).
    attribute :delivery_status, :atom do
      constraints one_of: [:pending, :delivered, :failed]
      allow_nil? false
      default :pending
      public? true
    end

    attribute :delivered_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :case, Bedrock.Compliance.Case do
      allow_nil? false
      attribute_writable? true
    end
  end

  # At most one Alert per Case — the precision channel points at a Case once.
  identities do
    identity :unique_case, [:case_id]
  end
end
