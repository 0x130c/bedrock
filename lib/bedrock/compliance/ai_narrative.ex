defmodule Bedrock.Compliance.AINarrative do
  @moduledoc """
  The LLM-written, human-readable summary of a `Case` produced by the Context
  Weaver (Layer 3). A convenience for fast comprehension — never a verdict, never
  signed on, and always subordinate to the `HardEvidence`. Carries the
  `machine_generated` label so it is unmistakably machine-produced context.

  Tenant-scoped; belongs to the `Case`. Distinct from `HardEvidence`: weaving a
  narrative never touches or overwrites the verdict-bearing facts.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAi]

  alias Bedrock.Compliance.ContextWeaver

  postgres do
    table "ai_narratives"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:summary, :model]
    end

    action :summarize, :string do
      description """
      Weave the Hard Evidence behind a Case into a short, plain-language narrative
      that explains what happened to an Auditor. Context only — never a verdict,
      never a recommendation to confirm or dismiss.
      """

      argument :control_name, :string, allow_nil?: false
      argument :reason, :string, allow_nil?: false
      argument :evidence, :map, allow_nil?: false

      run prompt(
            &ContextWeaver.model/0,
            req_llm: ContextWeaver.LLM,
            tools: false,
            prompt: {
              """
              You are the Context Weaver for a process-compliance auditor. You
              write a brief, plain-language narrative of a single compliance Case
              from its Hard Evidence so a human Auditor grasps it in seconds.

              You are an Investigator, not a Judge: explain and summarize the
              facts, but never issue a verdict, never decide whether the Case is
              confirmed or dismissed, and never recommend an action. The Hard
              Evidence is authoritative; your narrative is only context.
              """,
              """
              Control breached: <%= @input.arguments.control_name %>
              Deterministic reason: <%= @input.arguments.reason %>
              Hard Evidence (offending record snapshot):
              <%= Jason.encode!(@input.arguments.evidence) %>

              Write the narrative now.
              """
            }
          )
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :summary, :string do
      allow_nil? false
      public? true
    end

    # The narrative is always machine-produced context, plainly labeled as such.
    attribute :machine_generated, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :model, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :case, Bedrock.Compliance.Case do
      allow_nil? false
    end
  end
end
