defmodule Bedrock.Compliance.AnomalyDetector do
  @moduledoc """
  The contract every Layer-2 anomaly detector implements — the behavioural sibling
  of the deterministic `Bedrock.Compliance.Control`.

  A detector is pure: it extracts comparable `observation`s of one `metric` from a
  batch of normalized Odoo records, and turns a scored outlier into a candidate
  `Anomaly` finding. It owns *what* to measure (the metric and how to read it off
  the records) and *which tail is suspicious*; the maths of *how unusual* a value
  is lives once, in `Bedrock.Compliance.AnomalyDetection`.

  The same `observations/1` feeds both halves of the engine: backfill summarizes
  them into a `Baseline`, and live detection scores fresh ones against it. A
  detector raises suspicion, never a verdict — its `finding/2` is explicitly a
  candidate for human review.

  An `observation` is one measured value with the context to score and explain it:

    * `:entity_type` / `:entity_ref` — the Baseline this value belongs to
      (e.g. `{:process, "p2p"}` for a process-wide window, `{:vendor, id}` per vendor).
    * `:value` — the measured number scored against the Baseline.
    * `:evidence` — the snapshot (including any before/after diff) carried into a
      Case's Hard Evidence when this observation is an outlier.

  An `anomaly_finding` is the candidate the ingestion seam turns into a `Case`:

    * `:anomaly_type` / `:score` — what kind of outlier and its 0–100 Anomaly Score.
    * `:entity_ref` / `:subject` — the subject of the Anomaly and the Case title.
    * `:reason` — a human-readable, candidate-framed explanation.
    * `:evidence` — the Hard Evidence snapshot for the Case.
  """

  @type observation :: %{
          entity_type: atom(),
          entity_ref: String.t(),
          value: number(),
          evidence: map()
        }

  @type score_result :: Bedrock.Compliance.AnomalyDetection.score_result()

  @type anomaly_finding :: %{
          anomaly_type: atom(),
          score: integer(),
          entity_ref: String.t(),
          subject: String.t(),
          reason: String.t(),
          evidence: map()
        }

  @doc "The human-readable name of this detector, used in Anomaly reasons and Case titles."
  @callback detector_name() :: String.t()

  @doc "The Baseline metric this detector measures (the key its observations are scored against)."
  @callback metric() :: atom()

  @doc "Which tail of the Baseline is suspicious for this metric (`:both` when either is)."
  @callback relevant_direction() :: :low | :high | :both

  @doc "Extract the comparable observations of this detector's metric from a batch of records."
  @callback observations(records :: [map()]) :: [observation()]

  @doc "Build the candidate Anomaly finding for an observation that scored as an outlier."
  @callback finding(observation(), score_result()) :: anomaly_finding()

  @doc """
  The cross-batch correlation spec (ADR-0011) — the per-detector window the
  ingestion seam replays from the Event History before scoring. A detector that
  pairs events across batches (e.g. a bank change with a later payment) declares
  the `{types, key, lookback}` it correlates over; a detector that scores one event
  against a Baseline in isolation omits this callback and is fed only the batch.
  """
  @callback correlation() :: Bedrock.Compliance.EventHistory.spec()

  @optional_callbacks correlation: 0
end
