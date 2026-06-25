defmodule Bedrock.Compliance.Anomalies.BankChangeBeforePayment do
  @moduledoc """
  The flagship Layer-2 detector: a vendor's bank account is changed and a payment
  to that vendor follows within an *unusually short* window. Each step is innocuous
  alone; the tight gap between a payee-detail change and the money going out is the
  classic redirection-fraud signature.

  The measured `metric` is the change→payment window in hours, scored against a
  *process-wide* Baseline (`{:process, "p2p"}`) of how long that gap normally is —
  so "unusually short" means "shorter than almost every real transaction", the
  percentile read ADR-0006 calls out. Only the low tail is suspicious.

  Pure and parameter-free: it pairs each `:bank_account` change with the first
  payment to the same vendor at or after it, carrying the before/after diff
  (reconstructed from Odoo field-tracking) into the observation so it lands in the
  Case's Hard Evidence. A finding is explicitly a *candidate*, never a `Violation`.
  """
  @behaviour Bedrock.Compliance.AnomalyDetector

  @metric :bank_change_to_payment_hours
  @anomaly_type :bank_change_before_payment
  @detector_name "Bank account changed before payment"

  @impl true
  def detector_name, do: @detector_name

  @impl true
  def metric, do: @metric

  # A short gap is the suspicious one; paying long after a bank change is normal.
  @impl true
  def relevant_direction, do: :low

  @impl true
  def observations(records) do
    payments_by_vendor =
      records
      |> Enum.filter(&payment?/1)
      |> Enum.group_by(&Map.get(&1, :vendor_id))

    records
    |> Enum.filter(&bank_account_change?/1)
    |> Enum.flat_map(fn change ->
      payments = Map.get(payments_by_vendor, Map.get(change, :vendor_id), [])

      case first_payment_after(payments, Map.get(change, :occurred_at)) do
        nil -> []
        payment -> [observation(change, payment)]
      end
    end)
  end

  @impl true
  def finding(observation, score_result) do
    %{
      vendor_id: vendor_id,
      diff: diff,
      window_hours: window_hours,
      changed_at: changed_at,
      paid_at: paid_at
    } =
      observation.evidence

    longer_pct = round((1.0 - score_result.percentile) * 100)

    %{
      anomaly_type: @anomaly_type,
      score: score_result.score,
      entity_ref: vendor_id,
      # A bounded Episode: this specific change→payment pair. Re-ingesting it reopens
      # no second Case (ADR-0011).
      finding_key:
        "#{vendor_id}|#{DateTime.to_iso8601(changed_at)}|#{DateTime.to_iso8601(paid_at)}",
      subject: "Vendor #{vendor_id}",
      reason:
        "Anomaly candidate (not a verdict): vendor #{vendor_id}'s bank account changed from " <>
          "#{diff.before} to #{diff.after}, then a payment followed just " <>
          "#{Float.round(window_hours, 1)}h later — shorter than #{longer_pct}% of normal " <>
          "change-to-payment windows. Anomaly Score #{score_result.score}/100.",
      evidence: observation.evidence
    }
  end

  defp observation(change, payment) do
    changed_at = Map.get(change, :occurred_at)
    paid_at = Map.get(payment, :occurred_at)
    window_hours = DateTime.diff(paid_at, changed_at) / 3600

    %{
      entity_type: :process,
      entity_ref: "p2p",
      value: window_hours,
      evidence: %{
        vendor_id: Map.get(change, :vendor_id),
        diff: %{
          field: :bank_account,
          before: Map.get(change, :old_value),
          after: Map.get(change, :new_value)
        },
        changed_at: changed_at,
        paid_at: paid_at,
        window_hours: window_hours
      }
    }
  end

  defp first_payment_after(payments, changed_at) do
    payments
    |> Enum.filter(fn payment ->
      paid_at = Map.get(payment, :occurred_at)
      not is_nil(paid_at) and DateTime.compare(paid_at, changed_at) != :lt
    end)
    |> Enum.min_by(&Map.get(&1, :occurred_at), DateTime, fn -> nil end)
  end

  defp payment?(record) do
    Map.get(record, :type) == :payment and not is_nil(Map.get(record, :vendor_id)) and
      not is_nil(Map.get(record, :occurred_at))
  end

  defp bank_account_change?(record) do
    Map.get(record, :type) == :vendor_change and Map.get(record, :field) == :bank_account and
      not is_nil(Map.get(record, :vendor_id)) and not is_nil(Map.get(record, :occurred_at))
  end
end
