defmodule Bedrock.Compliance.Controls.ThresholdApproval do
  @moduledoc """
  Deterministic Layer-1 Control: a Purchase Order whose total exceeds an
  approval threshold must carry an approval from a required approver role.

  Pure and parameterized — no database, no AI. Given a normalized PO record and
  the activated parameters, it returns either a `{:violation, reason}` naming the
  Control and explaining the breach, or `:ok`. The source of truth for whether
  this rule is breached lives here and nowhere else.
  """
  @behaviour Bedrock.Compliance.Control

  @control_name "Threshold Approval"

  @impl true
  def control_name, do: @control_name

  @impl true
  def findings(records, opts) do
    Enum.flat_map(records, fn record ->
      case evaluate(record, opts) do
        {:violation, reason} ->
          [%{subject: "PO #{record[:id]}", evidence: record, reason: reason}]

        :ok ->
          []
      end
    end)
  end

  @doc """
  Evaluate one normalized PO record against the threshold-approval rule.

  Options:
    * `:threshold` — the amount above which approval is required
    * `:approver_role` — the role that must appear among the PO's approvals

  Returns `{:violation, reason}` when the PO total is strictly above the
  threshold and no approval from `approver_role` is present, otherwise `:ok`.
  """
  def evaluate(po, opts) do
    threshold = Keyword.fetch!(opts, :threshold)
    approver_role = Keyword.fetch!(opts, :approver_role)

    if over_threshold?(po, threshold) and not approved_by?(po, approver_role) do
      {:violation, reason(po, threshold, approver_role)}
    else
      :ok
    end
  end

  defp over_threshold?(po, threshold), do: amount_total(po) > threshold

  defp approved_by?(po, approver_role) do
    po
    |> Map.get(:approvals, [])
    |> Enum.any?(fn approval -> Map.get(approval, :role) == approver_role end)
  end

  defp amount_total(po), do: Map.get(po, :amount_total) || 0

  defp reason(po, threshold, approver_role) do
    "Control '#{@control_name}' breached: PO #{po[:id]} totaling " <>
      "#{format_money(amount_total(po), po[:currency])} exceeds the " <>
      "#{format_money(threshold, po[:currency])} approval threshold without a " <>
      "required #{approver_role} approval."
  end

  defp format_money(amount, currency) do
    formatted = amount |> Integer.to_string() |> add_thousands_separators()
    [formatted, currency] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp add_thousands_separators(digits) do
    digits
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
