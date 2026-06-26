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
      define :get_case, action: :read, get_by: [:id]
      define :triage_case, action: :triage
      define :investigate_case, action: :investigate
      define :confirm_case, action: :confirm
      define :accept_risk_case, action: :accept_risk
      define :dismiss_case, action: :dismiss
      define :close_case, action: :close
      define :export_case, action: :export
    end

    resource Bedrock.Compliance.Violation
    resource Bedrock.Compliance.ConformanceDeviation
    resource Bedrock.Compliance.Anomaly
    resource Bedrock.Compliance.HardEvidence
    resource Bedrock.Compliance.Attestation

    resource Bedrock.Compliance.Alert do
      define :promote_alert, action: :promote
      define :mark_alert_delivered, action: :mark_delivered
      define :list_alerts, action: :read
      define :get_alert, action: :read, get_by: [:id]
    end

    resource Bedrock.Compliance.SuppressionRule do
      define :create_suppression_rule, action: :create
      define :list_suppression_rules, action: :read
      define :matching_suppression_rules, action: :matching, args: [:control_name, :subject]
    end

    resource Bedrock.Compliance.ControlAlertStat do
      define :upsert_control_alert_stat, action: :upsert
      define :list_control_alert_stats, action: :read
      define :get_control_alert_stat, action: :read, get_by: [:control_name]
    end

    resource Bedrock.Compliance.QuarantineEntry do
      define :create_quarantine_entry, action: :create
      define :list_quarantine_entries, action: :read
    end

    resource Bedrock.Compliance.Event do
      define :upsert_event, action: :upsert
      define :list_events, action: :read
    end

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
