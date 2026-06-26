defmodule Bedrock.Compliance.PromotionGate do
  @moduledoc """
  The Alert promotion gate (ADR-0010), as a pure decision over a finding's gate
  context. Every finding opens a `Case` (the recall channel); this decides whether
  it *also* promotes to an `Alert` (the precision channel):

      promote? = (severity >= :critical or anomaly_score >= :high)
                 and money_at_risk >= materiality_floor
                 and not suppressed?
                 and baseline_mature?

  `decision/1` returns `:promote` or `{:case_only, reason}` — the reason names the
  first gate condition that blocked promotion, so a Case-only outcome is explainable.
  """

  alias Bedrock.Compliance.Severity

  # The Anomaly Score band that counts as "high" suspicion for promotion. An Anomaly
  # only becomes a candidate at all once it clears the detector's own (higher) score
  # threshold, so this is the floor the *precision* channel additionally requires.
  @high_anomaly_score 80

  # The precision channel additionally requires a *mature* Baseline behind an
  # Anomaly's score — enough history to trust an interrupting Alert. This is a
  # higher bar than the detector's own min-samples for raising a candidate at all.
  @mature_baseline_count 30

  @type context :: %{
          severity: Severity.t() | nil,
          anomaly_score: integer() | nil,
          money_at_risk: Money.t() | nil,
          materiality_floor: Money.t(),
          suppressed?: boolean(),
          baseline_mature?: boolean(),
          demoted?: boolean()
        }

  @doc "Decide whether a finding promotes to an Alert."
  @spec decision(context()) :: :promote | {:case_only, atom()}
  def decision(ctx) do
    cond do
      ctx.demoted? -> {:case_only, :control_demoted}
      ctx.suppressed? -> {:case_only, :suppressed}
      not strong_signal?(ctx) -> {:case_only, :weak_signal}
      not material?(ctx) -> {:case_only, :below_materiality_floor}
      not ctx.baseline_mature? -> {:case_only, :immature_baseline}
      true -> :promote
    end
  end

  @doc "The high-suspicion Anomaly Score band that gates promotion."
  @spec high_anomaly_score() :: integer()
  def high_anomaly_score, do: @high_anomaly_score

  @doc "The Baseline sample count at which an Anomaly's score is mature enough to Alert."
  @spec mature_baseline_count() :: integer()
  def mature_baseline_count, do: @mature_baseline_count

  # Deterministic Severity at least :critical, OR a high-suspicion Anomaly Score.
  defp strong_signal?(ctx) do
    critical_severity?(ctx.severity) or high_anomaly?(ctx.anomaly_score)
  end

  defp critical_severity?(nil), do: false
  defp critical_severity?(severity), do: Severity.at_least?(severity, :critical)

  defp high_anomaly?(score) when is_integer(score), do: score >= @high_anomaly_score
  defp high_anomaly?(_), do: false

  # Money at risk meets the Materiality Floor. A finding with no money at risk is
  # never material. Compared within a single currency (ADR-0011).
  defp material?(%{money_at_risk: nil}), do: false

  defp material?(%{money_at_risk: money, materiality_floor: floor}) do
    Money.compare(money, floor) in [:gt, :eq]
  end
end
