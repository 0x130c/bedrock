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

  # A large unapproved spend is the flagship critical breach — eligible for the
  # Alert precision channel (ADR-0010).
  @impl true
  def criticality, do: :critical

  @impl true
  def findings(records, opts) do
    Enum.flat_map(records, fn record ->
      case evaluate(record, opts) do
        {:violation, reason} ->
          # Episode-grained per Purchase Order: the same PO re-ingested reopens no
          # second Case (ADR-0011).
          [
            %{
              subject: "PO #{record[:id]}",
              finding_key: to_string(record[:id]),
              evidence: record,
              reason: reason,
              # The unapproved PO total is the money at risk the gate weighs against
              # the Materiality Floor (ADR-0010).
              money_at_risk: amount_total(record)
            }
          ]

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

  # Per-currency (ADR-0011): the PO total is a `Money`; the threshold is read in the
  # PO's own currency, so no cross-currency conversion ever happens. A PO with no
  # total cannot breach.
  defp over_threshold?(po, threshold) do
    case amount_total(po) do
      nil -> false
      amount -> Money.compare(amount, Money.new(amount.currency, threshold)) == :gt
    end
  end

  defp approved_by?(po, approver_role) do
    po
    |> Map.get(:approvals, [])
    |> Enum.any?(fn approval -> Map.get(approval, :role) == approver_role end)
  end

  defp amount_total(po), do: Map.get(po, :amount_total)

  defp reason(po, threshold, approver_role) do
    amount = amount_total(po)

    "Control '#{@control_name}' breached: PO #{po[:id]} totaling " <>
      "#{Money.to_string!(amount)} exceeds the " <>
      "#{Money.to_string!(Money.new(amount.currency, threshold))} approval threshold without a " <>
      "required #{approver_role} approval."
  end
end
