defmodule Bedrock.Test.RecordingAlertAdapter do
  @moduledoc """
  Deterministic stand-in for real Alert delivery, injected via
  `config :bedrock, :alert_delivery` so tests never hit Slack / Telegram / SMS /
  webhook. Each delivered Alert is recorded in order; a test resets the recording in
  `setup` and asserts on `deliveries/0`.

  Backed by an unlinked, named Agent so it survives across the actions under test
  (which may run in their own processes) rather than dying with one caller.
  """
  @behaviour Bedrock.Compliance.AlertDelivery

  @name __MODULE__

  @impl true
  def deliver(alert) do
    ensure_started()
    Agent.update(@name, &[alert | &1])
    {:ok, :recorded}
  end

  @doc "The Alerts delivered since the last reset, in delivery order."
  def deliveries do
    ensure_started()
    Agent.get(@name, &Enum.reverse/1)
  end

  @doc "Clear the recording — call in test setup."
  def reset do
    ensure_started()
    Agent.update(@name, fn _ -> [] end)
  end

  defp ensure_started do
    case Process.whereis(@name) do
      nil ->
        case Agent.start(fn -> [] end, name: @name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
