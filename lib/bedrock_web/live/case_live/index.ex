defmodule BedrockWeb.CaseLive.Index do
  @moduledoc """
  The Triage Queue (CONTEXT.md): the recall channel where every finding lands as a
  `Case` for review. Lists the Organization's Cases and links into each one's detail
  view. Tenant-scoped by the `:org_id` path segment.
  """
  use BedrockWeb, :live_view

  alias Bedrock.Compliance

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    tenant = "org_#{org_id}"
    cases = Compliance.list_cases!(tenant: tenant)

    {:ok,
     socket
     |> assign(org_id: org_id, tenant: tenant)
     |> assign(:cases, cases)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Triage Queue
        <:subtitle>Cases awaiting an Auditor's review</:subtitle>
      </.header>

      <.table id="cases" rows={@cases}>
        <:col :let={case_record} label="Title">
          <.link navigate={~p"/orgs/#{@org_id}/cases/#{case_record.id}"} class="font-semibold">
            {case_record.title}
          </.link>
        </:col>
        <:col :let={case_record} label="Status">{case_record.status}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
