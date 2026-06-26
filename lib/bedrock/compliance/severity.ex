defmodule Bedrock.Compliance.Severity do
  @moduledoc """
  The deterministic criticality of a finding as an ordinal band (CONTEXT.md):
  `:low < :medium < :high < :critical`. A `Control` declares its band via
  `criticality/0`; the Alert promotion gate (ADR-0010) reads it through
  `at_least?/2`. Money-at-risk is combined with this band at the gate itself (the
  Materiality Floor check), per ADR-0010's promotion formula.
  """

  @ranks %{low: 0, medium: 1, high: 2, critical: 3}

  @type t :: :low | :medium | :high | :critical

  @doc "The ordinal rank of a Severity band, for comparison."
  @spec rank(t()) :: 0..3
  def rank(severity), do: Map.fetch!(@ranks, severity)

  @doc "Whether `severity` is at least as critical as `threshold`."
  @spec at_least?(t(), t()) :: boolean()
  def at_least?(severity, threshold), do: rank(severity) >= rank(threshold)
end
