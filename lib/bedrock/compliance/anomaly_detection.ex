defmodule Bedrock.Compliance.AnomalyDetection do
  @moduledoc """
  The pure Layer-2 statistical core — the Anomaly Detection Engine's maths, with
  no database and no ML (ADR-0006). It does two things:

    * `summarize/1` reduces a sample of historical observations into a `Baseline`
      summary (count, mean, standard deviation, and the sorted samples).
    * `score/2` measures how unusual a single observation is against that summary,
      returning a 0–100 `Anomaly Score` plus the supporting percentile, z-score and
      which tail (`:low`/`:high`) the observation falls in.

  Scoring is a deterministic function of the seeded Baseline — the same summary and
  observation always produce the same score. The score expresses *suspicion*, never
  a verdict: it is the raw signal an `AnomalyDetector` turns into a candidate
  `Anomaly`.

  The score is the two-sided tail mass turned inside out: an observation at the
  median scores 0, and one beyond every sample scores 100. The flagship example
  ("shorter than 99.8% of normal transactions") is exactly this percentile read.
  """

  @type summary :: %{count: non_neg_integer(), mean: float(), stddev: float(), samples: [float()]}
  @type score_result :: %{
          score: integer(),
          percentile: float(),
          z_score: float(),
          direction: :low | :high
        }

  # The activated Layer-2 detectors, run by both backfill (to seed Baselines) and
  # ingestion (to score subsequent events). A per-Organization activation resource
  # arrives in a later slice, mirroring the Control library.
  @detectors [
    Bedrock.Compliance.Anomalies.BankChangeBeforePayment,
    Bedrock.Compliance.Anomalies.UnusualPaymentAmount
  ]

  @doc "The activated anomaly detectors."
  @spec detectors() :: [module()]
  def detectors, do: @detectors

  # An observation is only scored against a Baseline of at least this many samples
  # — too thin a Baseline has no "normal" worth deviating from. Outliers must clear
  # this Anomaly Score to become a candidate.
  @default_min_samples 5
  @default_score_threshold 95

  @doc """
  Live detection: score `detector`'s observations over a batch against the seeded
  `baselines` and return one candidate `Anomaly` finding per outlier.

  An observation is flagged only when a Baseline for its entity and metric exists
  with enough samples (`:min_samples`), its Anomaly Score clears `:score_threshold`,
  and it falls in the detector's suspicious tail. Without a Baseline (cold start) it
  is silently skipped — Layer 2 raises suspicion only where it has learned normal.
  """
  @spec anomalies(module(), [map()], [map()], keyword()) :: [map()]
  def anomalies(detector, records, baselines, opts \\ []) do
    threshold = Keyword.get(opts, :score_threshold, @default_score_threshold)
    min_samples = Keyword.get(opts, :min_samples, @default_min_samples)
    index = Map.new(baselines, &{{&1.entity_type, &1.entity_ref, &1.metric}, &1})

    for observation <- detector.observations(records),
        baseline =
          Map.get(
            index,
            {observation.entity_type, to_string(observation.entity_ref), detector.metric()}
          ),
        not is_nil(baseline) and baseline.count >= min_samples,
        result = score(to_summary(baseline), observation.value),
        result.score >= threshold,
        relevant?(detector.relevant_direction(), result.direction) do
      # Carry the Baseline's sample count onto the candidate so the promotion gate
      # (ADR-0010) can require a *mature* Baseline before alerting, without the
      # detector needing to know about the precision channel.
      detector.finding(observation, result) |> Map.put(:baseline_count, baseline.count)
    end
  end

  @doc """
  Backfill bootstrap: group a detector's observations over a historical batch by
  entity and summarize each into a `Baseline` map (the summary plus its
  `:entity_type`, `:entity_ref` and `:metric`), ready to persist.
  """
  @spec baselines_for(module(), [map()]) :: [map()]
  def baselines_for(detector, records) do
    # `entity_ref` is normalized to a string here (Odoo ids arrive as integers) so
    # the persisted Baseline and the live lookup key in `anomalies/4` always match.
    detector.observations(records)
    |> Enum.group_by(fn observation ->
      {observation.entity_type, to_string(observation.entity_ref)}
    end)
    |> Enum.map(fn {{entity_type, entity_ref}, observations} ->
      observations
      |> Enum.map(& &1.value)
      |> summarize()
      |> Map.merge(%{entity_type: entity_type, entity_ref: entity_ref, metric: detector.metric()})
    end)
  end

  @doc """
  Reduce a non-empty sample of numbers into a Baseline summary. The samples are
  stored sorted so `score/2` can read an exact empirical percentile.
  """
  @spec summarize([number()]) :: summary()
  def summarize([_ | _] = samples) do
    floats = Enum.map(samples, &(&1 / 1))
    sorted = Enum.sort(floats)
    n = length(sorted)
    mean = Enum.sum(sorted) / n
    variance = Enum.reduce(sorted, 0.0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / n

    %{count: n, mean: mean, stddev: :math.sqrt(variance), samples: sorted}
  end

  @doc """
  Score `observation` against a Baseline `summary`.

  `:percentile` is the fraction of the Baseline below the observation, counting
  ties as half (the tie-corrected empirical CDF), so a value equal to the smallest
  sample is the boundary of normal rather than an extreme outlier;
  `:direction` is `:low` when it sits in the bottom half and `:high` otherwise.
  `:score` is `100` at the extremes and `0` at the median. `:z_score` is the
  standard-deviation distance from the mean (`0.0` when the Baseline has no spread).
  """
  @spec score(summary(), number()) :: score_result()
  def score(%{samples: samples, mean: mean, stddev: stddev}, observation) do
    percentile = percentile_rank(samples, observation)
    tail = min(percentile, 1.0 - percentile)

    %{
      score: round(100 * (1.0 - 2 * tail)),
      percentile: percentile,
      z_score: z_score(observation, mean, stddev),
      direction: if(percentile < 0.5, do: :low, else: :high)
    }
  end

  # The tie-corrected empirical percentile: the fraction of the Baseline below the
  # observation, counting equal samples as half. 0.0 when the observation is below
  # the whole Baseline, 1.0 when it is above all of it; a value tying the smallest
  # sample lands just above 0.0 (the boundary of normal), not at it.
  defp percentile_rank(samples, observation) do
    n = length(samples)
    below = Enum.count(samples, &(&1 < observation))
    at_or_below = Enum.count(samples, &(&1 <= observation))
    (below + at_or_below) / (2 * n)
  end

  defp z_score(_observation, _mean, +0.0), do: 0.0
  defp z_score(observation, mean, stddev), do: (observation - mean) / stddev

  # A persisted Baseline carries the same fields `score/2` reads off a summary.
  defp to_summary(baseline) do
    %{samples: baseline.samples, mean: baseline.mean, stddev: baseline.stddev}
  end

  defp relevant?(:both, _direction), do: true
  defp relevant?(direction, direction), do: true
  defp relevant?(_relevant, _direction), do: false
end
