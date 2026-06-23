defmodule Bedrock.Test.ContextWeaverStub do
  @moduledoc """
  Deterministic stand-in for `ReqLLM`, injected via
  `config :bedrock, :context_weaver_llm` so Context Weaver tests never make real
  LLM calls. Per-test behavior is driven by `:context_weaver_stub`:

    * `{:ok, text}` — return that exact narrative
    * `{:error, reason}` — fail generation (exercises graceful degradation)
    * `:echo` — return a narrative that embeds the prompt context (proves the
      Hard Evidence reached the weaver)
    * `:ok` / unset — return a generic canned narrative

  Mirrors `ReqLLM.generate_object/4`'s success shape:
  `{:ok, %{object: %{"result" => string}}}`.
  """

  def generate_object(_model, context, _schema, _opts) do
    case Application.get_env(:bedrock, :context_weaver_stub, :ok) do
      {:ok, text} ->
        {:ok, %{object: %{"result" => text}}}

      {:error, _reason} = error ->
        error

      :echo ->
        {:ok, %{object: %{"result" => "Machine-generated context. " <> context_text(context)}}}

      :ok ->
        {:ok, %{object: %{"result" => "Machine-generated summary of the compliance Case."}}}
    end
  end

  defp context_text(%{messages: messages}) when is_list(messages) do
    messages
    |> Enum.flat_map(fn message -> message |> Map.get(:content) |> List.wrap() end)
    |> Enum.map(&part_text/1)
    |> Enum.join("\n")
  end

  defp context_text(_), do: ""

  defp part_text(text) when is_binary(text), do: text
  defp part_text(%{text: text}) when is_binary(text), do: text
  defp part_text(_), do: ""
end
