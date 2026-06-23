defmodule Bedrock.Compliance.ContextWeaver do
  @moduledoc """
  Layer 3 — the Context Weaver. The LLM seam that turns a `Case`'s Hard Evidence
  into a plain-language `AINarrative` an Auditor can grasp in ~30 seconds. It
  *explains and summarizes*; it never decides logic or issues a verdict, and its
  output is always subordinate to the Hard Evidence (CONTEXT.md, ADR-0004).

  Narrative generation runs asynchronously off the verdict path (an AshOban
  trigger on `Case`), so a slow or failing LLM never blocks or alters the Case.
  """

  @default_model "anthropic:claude-haiku-4-5"

  @doc """
  The ReqLLM model specification the Context Weaver runs on. Configurable via
  `config :bedrock, :context_weaver_model`, defaulting to a fast Claude model.
  """
  def model do
    Application.get_env(:bedrock, :context_weaver_model, @default_model)
  end

  defmodule LLM do
    @moduledoc """
    Indirection in front of `ReqLLM` so the Context Weaver's LLM can be swapped
    for a deterministic fake in tests (no external calls). Configured via
    `config :bedrock, :context_weaver_llm`, defaulting to `ReqLLM`.
    """
    def generate_object(model, context, schema, opts) do
      impl().generate_object(model, context, schema, opts)
    end

    defp impl, do: Application.get_env(:bedrock, :context_weaver_llm, ReqLLM)
  end
end
