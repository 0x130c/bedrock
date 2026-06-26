defmodule BedrockWeb.CaseLive.Show do
  @moduledoc """
  The Case detail view of the Auditor workbench. Surfaces the verdict-bearing Hard
  Evidence and, separately and subordinately, the machine-written AI Narrative
  (CONTEXT.md). The Auditor drives the Case through its lifecycle from here.
  Tenant-scoped by the `:org_id` path segment.
  """
  use BedrockWeb, :live_view

  alias Bedrock.Compliance

  @loads [:violation, :hard_evidence, :ai_narrative, :attestation]

  # The argument-free lifecycle transitions, keyed by their phx-click event. `dismiss`
  # (needs a reason) and `close` (needs an attesting Auditor) are handled separately.
  @simple_transitions %{
    "triage" => &Compliance.triage_case/2,
    "investigate" => &Compliance.investigate_case/2,
    "confirm" => &Compliance.confirm_case/2,
    "accept_risk" => &Compliance.accept_risk_case/2,
    "export" => &Compliance.export_case/2
  }
  @simple_transition_events Map.keys(@simple_transitions)

  @impl true
  def mount(%{"org_id" => org_id, "id" => id}, _session, socket) do
    tenant = "org_#{org_id}"
    case_record = Compliance.get_case!(id, load: @loads, tenant: tenant)

    {:ok,
     socket
     |> assign(org_id: org_id, tenant: tenant)
     |> assign(:case, case_record)
     |> assign(:dismiss_form, to_form(%{"reason" => ""}, id: "dismiss-form"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@case.title}
        <:subtitle>Status: <span class="font-mono">{@case.status}</span></:subtitle>
      </.header>

      <section class="mt-6">
        <h2 class="text-base font-semibold">Hard Evidence</h2>
        <p class="text-sm text-base-content/70">
          The verdict-bearing, system-recorded facts behind this Case.
        </p>
        <dl class="mt-2 divide-y divide-base-200 rounded-lg border border-base-200">
          <div :for={{key, value} <- @case.hard_evidence.snapshot} class="flex gap-4 px-4 py-2">
            <dt class="w-40 font-mono text-sm text-base-content/70">{key}</dt>
            <dd class="font-mono text-sm">{format_value(value)}</dd>
          </div>
        </dl>
      </section>

      <section class="mt-6">
        <h2 class="text-base font-semibold">AI Narrative</h2>
        <p class="text-sm text-base-content/70">
          Machine-written context only — never a verdict, always subordinate to the Hard Evidence.
        </p>
        <div :if={@case.ai_narrative} class="mt-2 rounded-lg border border-base-200 px-4 py-3">
          <p class="text-sm">{@case.ai_narrative.summary}</p>
          <p class="mt-2 text-xs uppercase tracking-wide text-base-content/50">
            Machine-generated
          </p>
        </div>
        <p :if={is_nil(@case.ai_narrative)} class="mt-2 text-sm text-base-content/50">
          No narrative woven yet.
        </p>
      </section>

      <section
        :if={@case.attestation}
        class="mt-6 rounded-lg border border-success/40 bg-success/5 px-4 py-3"
      >
        <h2 class="text-base font-semibold">Attestation</h2>
        <p class="text-sm">
          Attested by <span class="font-semibold">{@case.attestation.auditor_email}</span>
          at {@case.attestation.attested_at}.
        </p>
        <p class="mt-1 text-xs text-base-content/60">
          An internal, identity-bound assertion that a human reviewed the Hard Evidence — not a
          chữ ký số (Digital Signature).
        </p>
      </section>

      <section class="mt-6">
        <h2 class="text-base font-semibold">Decision</h2>
        <p class="text-sm text-base-content/70">
          The Auditor weighs the Hard Evidence and decides — the system never issues a verdict.
        </p>
        <div class="mt-2 flex flex-wrap gap-2">
          <.button :for={{event, label} <- available_actions(@case.status)} phx-click={event}>
            {label}
          </.button>
        </div>

        <.form
          :if={@case.status == :investigating}
          for={@dismiss_form}
          id="dismiss-form"
          phx-submit="dismiss"
          class="mt-4 max-w-lg space-y-2"
        >
          <.input
            field={@dismiss_form[:reason]}
            type="textarea"
            label="Dismissal reason"
            placeholder="Why is this not a real issue? (recorded, later feeds Suppression Rules)"
          />
          <.button>Dismiss</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:ok, _} =
      Compliance.close_case(socket.assigns.case,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.tenant
      )

    {:noreply, reload_case(socket)}
  end

  @impl true
  def handle_event("dismiss", %{"reason" => reason}, socket) do
    case Compliance.dismiss_case(socket.assigns.case, %{reason: reason},
           tenant: socket.assigns.tenant
         ) do
      {:ok, _} ->
        {:noreply, reload_case(socket)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "A dismissal reason is required.")
         |> assign(:dismiss_form, to_form(%{"reason" => reason}, id: "dismiss-form"))}
    end
  end

  @impl true
  def handle_event(event, _params, socket) when event in @simple_transition_events do
    {:ok, _} =
      Map.fetch!(@simple_transitions, event).(socket.assigns.case, tenant: socket.assigns.tenant)

    {:noreply, reload_case(socket)}
  end

  # The lifecycle controls offered for the Case's current status (CONTEXT.md, ADR-0008).
  defp available_actions(:open), do: [{"triage", "Triage"}]
  defp available_actions(:triaged), do: [{"investigate", "Investigate"}]

  defp available_actions(:investigating),
    do: [{"confirm", "Confirm"}, {"accept_risk", "Accept Risk"}]

  defp available_actions(:confirmed), do: [{"close", "Close & Attest"}]
  defp available_actions(:dismissed), do: [{"close", "Close & Attest"}]
  defp available_actions(:accepted_risk), do: [{"close", "Close & Attest"}]
  defp available_actions(:closed), do: [{"export", "Export"}]
  defp available_actions(_status), do: []

  defp reload_case(socket) do
    case_record =
      Compliance.get_case!(socket.assigns.case.id, load: @loads, tenant: socket.assigns.tenant)

    assign(socket, :case, case_record)
  end

  # Hard Evidence values are JSON scalars or nested maps (e.g. a Money amount); render
  # them readably without leaking Elixir map syntax into the page.
  defp format_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_value(value), do: to_string(value)
end
