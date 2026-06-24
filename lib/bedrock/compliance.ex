defmodule Bedrock.Compliance do
  @moduledoc """
  The compliance auditing domain: tenants (`Organization`), their Odoo
  `Connection`s, and the detection seam (`ingest_events`) that turns normalized
  Odoo records into `Violation`s bundled into a `Case` with `HardEvidence`.

  Tenant-scoped resources (`Connection`, `Case`, `Violation`, `HardEvidence`)
  live in a per-`Organization` Postgres schema (ADR-0007).
  """
  use Ash.Domain,
    otp_app: :bedrock,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Bedrock.Compliance.Organization do
      define :create_organization, action: :create
      define :get_organization, action: :read, get_by: [:id]
    end

    resource Bedrock.Compliance.Connection do
      define :create_connection, action: :create
      define :ingest_events, action: :ingest_events, args: [:connection, :records]
      define :backfill_baselines, action: :backfill_baselines, args: [:connection, :records]
    end

    resource Bedrock.Compliance.Baseline do
      define :create_baseline, action: :create
      define :list_baselines, action: :read
    end

    resource Bedrock.Compliance.Case do
      define :open_case, action: :open
      define :open_conformance_case, action: :open_conformance
      define :open_anomaly_case, action: :open_anomaly
      define :list_cases, action: :read
    end

    resource Bedrock.Compliance.Violation
    resource Bedrock.Compliance.ConformanceDeviation
    resource Bedrock.Compliance.Anomaly
    resource Bedrock.Compliance.HardEvidence

    # The canonical P2P Process state machine: never persisted, only its
    # transition table is read by the Conformance checker (ADR-0004).
    resource Bedrock.Compliance.Process

    resource Bedrock.Compliance.ProcessInstance do
      define :create_process_instance, action: :create
      define :list_process_instances, action: :read
    end

    resource Bedrock.Compliance.AINarrative do
      define :summarize, action: :summarize, args: [:control_name, :reason, :evidence]
    end
  end
end
