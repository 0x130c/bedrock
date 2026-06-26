defmodule Bedrock.Compliance.AlertDelivery.Adapters do
  @moduledoc """
  The transport adapters behind the Alert delivery port (ADR-0002). The generic
  `Webhook` adapter is functional (a JSON `POST` via `Req`, the integration seam a
  customer-side Actuator listens on); `Slack`, `Telegram` and `Sms` are stubs in v1,
  awaiting per-Organization channel configuration in a later slice. Each is a
  `Bedrock.Compliance.AlertDelivery` adapter.
  """

  defmodule Webhook do
    @moduledoc """
    Generic outbound webhook: POSTs the Alert as JSON to the configured endpoint
    (`config :bedrock, :alert_webhook_url`). The customer-side Actuator reacts to it
    (ADR-0002). With no endpoint configured there is nowhere to deliver.
    """
    @behaviour Bedrock.Compliance.AlertDelivery

    @impl true
    def deliver(alert) do
      case Application.get_env(:bedrock, :alert_webhook_url) do
        nil ->
          {:error, :no_webhook_endpoint}

        url ->
          payload = %{
            alert_id: alert.id,
            case_id: alert.case_id,
            severity: alert.severity,
            anomaly_score: alert.anomaly_score
          }

          case Req.post(url, json: payload) do
            {:ok, %Req.Response{status: status}} when status in 200..299 -> {:ok, status}
            {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defmodule Slack do
    @moduledoc "Slack delivery — stub in v1 (channel configuration deferred)."
    @behaviour Bedrock.Compliance.AlertDelivery

    @impl true
    def deliver(_alert), do: {:error, :not_configured}
  end

  defmodule Telegram do
    @moduledoc "Telegram delivery — stub in v1 (channel configuration deferred)."
    @behaviour Bedrock.Compliance.AlertDelivery

    @impl true
    def deliver(_alert), do: {:error, :not_configured}
  end

  defmodule Sms do
    @moduledoc "SMS delivery — stub in v1 (channel configuration deferred)."
    @behaviour Bedrock.Compliance.AlertDelivery

    @impl true
    def deliver(_alert), do: {:error, :not_configured}
  end
end
