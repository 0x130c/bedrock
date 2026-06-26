defmodule Bedrock.Compliance.PromotionGateTest do
  @moduledoc """
  The pure promotion-gate decision (ADR-0010), tested directly: each gate condition
  and the precedence among them, with no database.
  """
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.PromotionGate

  # A context that clears every condition — each test perturbs one field.
  defp promotable(overrides \\ %{}) do
    Map.merge(
      %{
        severity: :critical,
        anomaly_score: nil,
        money_at_risk: Money.new(:VND, 800_000_000),
        materiality_floor: Money.new(:VND, 10_000_000),
        suppressed?: false,
        baseline_mature?: true,
        demoted?: false
      },
      overrides
    )
  end

  test "promotes when severity is critical, material, unsuppressed and mature" do
    assert PromotionGate.decision(promotable()) == :promote
  end

  test "promotes a pure Anomaly via a high Anomaly Score with no deterministic severity" do
    ctx = promotable(%{severity: nil, anomaly_score: PromotionGate.high_anomaly_score()})
    assert PromotionGate.decision(ctx) == :promote
  end

  test "a sub-critical severity with a low score is a weak signal" do
    ctx = promotable(%{severity: :high, anomaly_score: PromotionGate.high_anomaly_score() - 1})
    assert PromotionGate.decision(ctx) == {:case_only, :weak_signal}
  end

  test "money below the Materiality Floor blocks promotion" do
    ctx = promotable(%{money_at_risk: Money.new(:VND, 5_000_000)})
    assert PromotionGate.decision(ctx) == {:case_only, :below_materiality_floor}
  end

  test "no money at risk is never material" do
    assert PromotionGate.decision(promotable(%{money_at_risk: nil})) ==
             {:case_only, :below_materiality_floor}
  end

  test "an immature baseline blocks promotion" do
    assert PromotionGate.decision(promotable(%{baseline_mature?: false})) ==
             {:case_only, :immature_baseline}
  end

  test "a matching Suppression Rule blocks promotion" do
    assert PromotionGate.decision(promotable(%{suppressed?: true})) == {:case_only, :suppressed}
  end

  test "a demoted Control blocks promotion even with an otherwise-promotable finding" do
    assert PromotionGate.decision(promotable(%{demoted?: true})) ==
             {:case_only, :control_demoted}
  end

  test "demotion takes precedence over suppression and signal" do
    ctx = promotable(%{demoted?: true, suppressed?: true, severity: :low})
    assert PromotionGate.decision(ctx) == {:case_only, :control_demoted}
  end
end
