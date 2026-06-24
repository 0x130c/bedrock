defmodule Bedrock.Compliance.AnomalyDetectionTest do
  @moduledoc """
  Unit coverage of the pure Layer-2 statistical core: building a Baseline summary
  from samples and scoring an observation against it. No database, no AI — the
  source of truth for "how unusual is this" lives here. Scoring is deterministic,
  so the assertions pin exact Anomaly Scores.
  """
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.AnomalyDetection

  # Normal change→payment windows, in hours: roughly 5–15 days, well clear of zero.
  @windows [120.0, 168.0, 200.0, 240.0, 300.0, 360.0, 240.0, 180.0, 210.0, 280.0]

  describe "score/2" do
    test "an observation below the whole Baseline scores ~100 on the low side" do
      baseline = AnomalyDetection.summarize(@windows)

      # Paid one hour after the bank account changed — shorter than every normal window.
      result = AnomalyDetection.score(baseline, 1.0)

      assert result.score == 100
      assert result.direction == :low
      assert result.percentile == 0.0
    end

    test "an observation near the Baseline median is not an outlier" do
      baseline = AnomalyDetection.summarize(@windows)

      # 225h sits in the middle of the normal windows — unremarkable.
      result = AnomalyDetection.score(baseline, 225.0)

      assert result.score <= 20
    end

    test "an observation equal to the smallest sample is not a maximal outlier" do
      baseline = AnomalyDetection.summarize(@windows)

      # 120h ties the fastest *normal* change→payment window already in the Baseline,
      # so it is the boundary of normal — not "shorter than every normal window".
      # Ties must not score as if the observation sat below the whole Baseline.
      result = AnomalyDetection.score(baseline, 120.0)

      assert result.score < 95
      assert result.direction == :low
    end
  end
end
