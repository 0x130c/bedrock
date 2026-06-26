defmodule Bedrock.Compliance.ControlAlertStat do
  @moduledoc """
  Per-Control Alert outcomes, for self-tuning (ADR-0010). Each resolved Alert is
  tallied here: `resolved_count` over all alerted Cases that reached a decision, and
  `actioned_count` over the subset the Auditor confirmed or accepted-risk on. When a
  Control's Alert precision (`actioned / resolved`) falls below target with enough
  samples, it is demoted to Case-only — `demoted_at` marks when. Tenant-scoped;
  unique per Control.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "control_alert_stats"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read]

    create :upsert do
      primary? true
      upsert? true
      upsert_identity :unique_control
      accept [:control_name, :resolved_count, :actioned_count, :demoted_at]
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

    # Alerted Cases for this Control that reached a decision.
    attribute :resolved_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    # The subset that was actioned (confirmed or accepted-risk).
    attribute :actioned_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    # When the Control was auto-demoted to Case-only; nil while it still alerts.
    attribute :demoted_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_control, [:control_name]
  end
end
