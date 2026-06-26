defmodule Bedrock.Compliance.AlertPrecision do
  @moduledoc """
  Self-tuning of the precision channel (ADR-0010). Records each resolved Alert's
  outcome against its Control's running tally and auto-demotes a Control whose Alert
  precision (`actioned / resolved`) falls below target once enough Alerts have
  resolved — no single noisy Control may train Auditors to ignore Alerts.

  `record_outcome/3` is called as an alerted Case reaches a decision; `demoted?/2`
  is read by the promotion gate before alerting.
  """
  alias Bedrock.Compliance
  alias Bedrock.Compliance.ControlAlertStat

  # The Alert precision a Control must hold; below it (with enough samples) the
  # Control is demoted to Case-only.
  @demote_below 0.5

  # Demotion only kicks in once a Control has this many resolved Alerts, so a single
  # early dismissal never demotes a Control on noise.
  @min_resolved_for_demotion 3

  @doc "The Alert precision target below which a Control demotes."
  def demote_below, do: @demote_below

  @doc "The resolved-Alert sample size required before a Control can demote."
  def min_resolved_for_demotion, do: @min_resolved_for_demotion

  @doc """
  Tally one resolved Alert for `control_name` (`actioned?` true when its Case was
  confirmed or accepted-risk) and re-evaluate demotion. Upserts the Control's stat.
  """
  def record_outcome(control_name, actioned?, tenant) do
    stat = current(control_name, tenant)
    resolved = stat.resolved_count + 1
    actioned = stat.actioned_count + if actioned?, do: 1, else: 0

    Compliance.upsert_control_alert_stat!(
      %{
        control_name: control_name,
        resolved_count: resolved,
        actioned_count: actioned,
        demoted_at: demoted_at(stat.demoted_at, resolved, actioned)
      },
      tenant: tenant
    )
  end

  @doc "Whether `control_name` has been auto-demoted to Case-only."
  def demoted?(control_name, tenant) do
    case lookup(control_name, tenant) do
      %ControlAlertStat{demoted_at: demoted_at} -> not is_nil(demoted_at)
      nil -> false
    end
  end

  defp current(control_name, tenant) do
    lookup(control_name, tenant) || %{resolved_count: 0, actioned_count: 0, demoted_at: nil}
  end

  defp lookup(control_name, tenant) do
    case Compliance.get_control_alert_stat(control_name, tenant: tenant) do
      {:ok, %ControlAlertStat{} = stat} -> stat
      _ -> nil
    end
  end

  # Once demoted, a Control stays demoted. Otherwise it demotes when enough Alerts
  # have resolved and precision has fallen below target.
  defp demoted_at(existing, _resolved, _actioned) when not is_nil(existing), do: existing

  defp demoted_at(_existing, resolved, actioned) do
    if resolved >= @min_resolved_for_demotion and actioned / resolved < @demote_below do
      DateTime.utc_now()
    end
  end
end
