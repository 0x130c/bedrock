defmodule Bedrock.Compliance.Backfill do
  @moduledoc """
  Implementation of the `backfill_baselines` action — the Layer-2 onboarding step
  (ADR-0006). Given a batch of historical fixture events, it runs every activated
  anomaly detector's observation extractor, summarizes the observations per entity
  into a `Baseline`, and persists them (upserting on each Baseline's natural key).

  This solves the cold-start: once Baselines exist, `ingest_events` can score
  subsequent events against them. Backfill only learns "normal" — it never opens a
  Case.
  """
  use Ash.Resource.Actions.Implementation

  alias Bedrock.Compliance
  alias Bedrock.Compliance.{AnomalyDetection, Normalizer}

  @impl true
  def run(input, _opts, _context) do
    tenant = input.tenant
    # Same field contract as live ingest (ADR-0011): seed Baselines from the coerced
    # shape so a metric learned at backfill matches the one scored at ingest.
    {records, _quarantined} = Normalizer.normalize(input.arguments.records)

    baselines =
      for detector <- AnomalyDetection.detectors(),
          attrs <- AnomalyDetection.baselines_for(detector, records) do
        Compliance.create_baseline!(attrs, tenant: tenant)
      end

    {:ok, baselines}
  end
end
