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
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban]

  postgres do
    table "cases"
    repo Bedrock.Repo
  end

  oban do
    triggers do
      # Layer 3 weaving runs off the verdict path: enqueued programmatically by
      # `ingest_events` once a Case is committed (scheduler disabled). A failed
      # weave fails only this job; the Case verdict is never blocked or altered.
      trigger :weave_narrative do
        action :weave_narrative
        worker_read_action :read
        where expr(is_nil(narrative_woven_at))
        queue :weave_narrative
        scheduler_cron false
        max_attempts 1
        worker_module_name Bedrock.Compliance.Case.AshOban.Worker.WeaveNarrative
      end
    end
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

    update :weave_narrative do
      description "Weave the AINarrative for this Case from its Hard Evidence (Layer 3)."
      require_atomic? false

      change Bedrock.Compliance.Changes.WeaveNarrative
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

    # Set when the Context Weaver has woven (or is woven for) this Case; nil means
    # no narrative yet. Drives the weave trigger's `where` filter.
    attribute :narrative_woven_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    has_one :violation, Bedrock.Compliance.Violation
    has_one :hard_evidence, Bedrock.Compliance.HardEvidence
    has_one :ai_narrative, Bedrock.Compliance.AINarrative
  end
end
