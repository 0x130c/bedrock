defmodule Bedrock.Compliance.Anomalies.UnusualPaymentAmount do
  @moduledoc """
  A generic Layer-2 detector: a payment whose amount is unusually large for the
  vendor it goes to. Measured against a *per-vendor* Baseline of payment amounts —
  each vendor's normal invoice size differs, so a 480M payment is unremarkable for
  one vendor and a glaring outlier for another that normally bills 10M.

  Pure and parameter-free: it reads each payment's amount off the batch and scores
  it against the vendor's `:payment_amount` Baseline. Only the high tail is
  suspicious (an unusually *large* payment is the money-at-risk signal). A finding
  is explicitly a *candidate*, never a `Violation` — money-at-risk severity and any
  rule breach are the deterministic Layer-1 Controls' concern.
  """
  @behaviour Bedrock.Compliance.AnomalyDetector

  @metric :payment_amount
  @anomaly_type :unusual_payment_amount
  @detector_name "Unusual payment amount"

  @impl true
  def detector_name, do: @detector_name

  @impl true
  def metric, do: @metric

  @impl true
  def relevant_direction, do: :high

  @impl true
  def observations(records) do
    records
    |> Enum.filter(&payment?/1)
    |> Enum.map(fn payment ->
      vendor_id = Map.get(payment, :vendor_id)
      amount = Map.get(payment, :amount_total)

      %{
        entity_type: :vendor,
        entity_ref: vendor_id,
        # The statistical core scores numbers; the normalized `Money` is reduced to
        # its numeric amount for scoring while the Money stays in the evidence.
        value: amount_value(amount),
        evidence: %{vendor_id: vendor_id, amount: amount, po_ref: Map.get(payment, :po_ref)}
      }
    end)
  end

  defp amount_value(%Money{} = amount), do: amount |> Money.to_decimal() |> Decimal.to_float()
  defp amount_value(amount) when is_number(amount), do: amount / 1

  @impl true
  def finding(observation, score_result) do
    %{vendor_id: vendor_id, amount: amount, po_ref: po_ref} = observation.evidence
    smaller_pct = round(score_result.percentile * 100)

    %{
      anomaly_type: @anomaly_type,
      score: score_result.score,
      entity_ref: vendor_id,
      # A bounded Episode: this specific oversized payment. Re-ingesting it reopens no
      # second Case (ADR-0011).
      finding_key: "#{vendor_id}|#{po_ref}|#{amount}",
      subject: "Vendor #{vendor_id}",
      reason:
        "Anomaly candidate (not a verdict): a payment of #{amount} to vendor #{vendor_id} is " <>
          "unusually large — larger than #{smaller_pct}% of its normal payments. " <>
          "Anomaly Score #{score_result.score}/100.",
      evidence: observation.evidence
    }
  end

  defp payment?(record) do
    Map.get(record, :type) == :payment and not is_nil(Map.get(record, :vendor_id)) and
      amount?(Map.get(record, :amount_total))
  end

  defp amount?(%Money{}), do: true
  defp amount?(amount), do: is_number(amount)
end
