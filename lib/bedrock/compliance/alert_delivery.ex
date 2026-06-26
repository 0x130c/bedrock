defmodule Bedrock.Compliance.AlertDelivery do
  @moduledoc """
  The Alert delivery port (ADR-0002, ADR-0010). Bedrock realizes preventive value by
  *signalling* only — it emits an Alert and the customer's Actuator acts. Which
  transport carries the Alert (Slack / Telegram / SMS / webhook) is swappable behind
  this port: production routes by the Alert's channel via `Dispatch`, while tests
  inject a recording adapter and assert on what it captured, never a real call.

  Configured via `config :bedrock, :alert_delivery`, defaulting to `Dispatch`.
  """

  @doc "Deliver an Alert over its channel. Returns `{:ok, info}` or `{:error, reason}`."
  @callback deliver(alert :: struct()) :: {:ok, term()} | {:error, term()}

  @spec deliver(struct()) :: {:ok, term()} | {:error, term()}
  def deliver(alert), do: adapter().deliver(alert)

  defp adapter, do: Application.get_env(:bedrock, :alert_delivery, __MODULE__.Dispatch)
end
