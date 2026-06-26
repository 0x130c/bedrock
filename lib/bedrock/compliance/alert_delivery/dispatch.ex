defmodule Bedrock.Compliance.AlertDelivery.Dispatch do
  @moduledoc """
  The production Alert delivery adapter: routes an Alert to the transport adapter for
  its channel (ADR-0002). In v1 only the generic webhook is functional; the
  Slack / Telegram / SMS adapters are stubs awaiting per-Organization configuration.
  """
  @behaviour Bedrock.Compliance.AlertDelivery

  alias Bedrock.Compliance.AlertDelivery.Adapters

  @impl true
  def deliver(%{channel: channel} = alert), do: adapter_for(channel).deliver(alert)

  defp adapter_for(:webhook), do: Adapters.Webhook
  defp adapter_for(:slack), do: Adapters.Slack
  defp adapter_for(:telegram), do: Adapters.Telegram
  defp adapter_for(:sms), do: Adapters.Sms
  defp adapter_for(_other), do: Adapters.Webhook
end
