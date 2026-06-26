defmodule BedrockWeb.CaseLiveTest do
  @moduledoc """
  The Auditor workbench LiveViews (issue #7): the Triage Queue lists Cases, the
  detail view shows Hard Evidence + AI Narrative, and the Auditor drives the Case
  through its lifecycle — dismissing with a reason and attesting on close.
  """
  use BedrockWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bedrock.Compliance

  setup :register_and_sign_in_user

  setup do
    org =
      Compliance.create_organization!(%{name: "Acme #{System.unique_integer([:positive])}"})

    %{org: org}
  end

  defp open_case(org, title) do
    Compliance.open_case!(
      %{
        title: title,
        violation: %{control_name: "Threshold Approval", reason: "PO0042 missing CFO"},
        hard_evidence: %{snapshot: %{"id" => "PO0042"}}
      },
      tenant: org
    )
  end

  defp weave_narrative(case_record, org, summary) do
    Bedrock.Compliance.AINarrative
    |> Ash.Changeset.for_create(:create, %{summary: summary}, tenant: org)
    |> Ash.Changeset.manage_relationship(:case, case_record, type: :append)
    |> Ash.create!()
  end

  describe "Triage Queue" do
    test "lists the Organization's Cases by title", %{conn: conn, org: org} do
      open_case(org, "PO0042 above threshold without CFO approval")

      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.id}/cases")

      assert html =~ "Triage Queue"
      assert html =~ "PO0042 above threshold without CFO approval"
    end
  end

  describe "Case detail" do
    test "shows the Hard Evidence and the AI Narrative", %{conn: conn, org: org} do
      case_record = open_case(org, "PO0042 above threshold")
      weave_narrative(case_record, org, "An auditor-friendly summary of PO0042.")

      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      assert html =~ "Hard Evidence"
      assert html =~ "PO0042"
      assert html =~ "AI Narrative"
      assert html =~ "An auditor-friendly summary of PO0042."
    end
  end

  describe "lifecycle controls" do
    test "the Auditor can triage an open Case from the detail view", %{conn: conn, org: org} do
      case_record = open_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html = view |> element("button", "Triage") |> render_click()

      assert html =~ "triaged"
      assert Ash.reload!(case_record, tenant: org).status == :triaged
    end

    test "the Auditor can investigate a triaged Case", %{conn: conn, org: org} do
      {:ok, triaged} =
        open_case(org, "PO0042 above threshold") |> Compliance.triage_case(tenant: org)

      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{triaged.id}")

      html = view |> element("button", "Investigate") |> render_click()

      assert html =~ "investigating"
      assert Ash.reload!(triaged, tenant: org).status == :investigating
    end

    defp investigating_case(org, title) do
      {:ok, triaged} = open_case(org, title) |> Compliance.triage_case(tenant: org)
      {:ok, investigating} = Compliance.investigate_case(triaged, tenant: org)
      investigating
    end

    test "the Auditor can confirm an investigating Case", %{conn: conn, org: org} do
      case_record = investigating_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html = view |> element("button", "Confirm") |> render_click()

      assert html =~ "confirmed"
      assert Ash.reload!(case_record, tenant: org).status == :confirmed
    end

    test "the Auditor can accept the risk on an investigating Case", %{conn: conn, org: org} do
      case_record = investigating_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html = view |> element("button", "Accept Risk") |> render_click()

      assert html =~ "accepted_risk"
      assert Ash.reload!(case_record, tenant: org).status == :accepted_risk
    end

    test "the Auditor dismisses an investigating Case with a reason", %{conn: conn, org: org} do
      case_record = investigating_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html =
        view
        |> form("#dismiss-form", %{"reason" => "Known month-end pattern"})
        |> render_submit()

      assert html =~ "dismissed"

      reloaded = Ash.reload!(case_record, tenant: org)
      assert reloaded.status == :dismissed
      assert reloaded.dismissal_reason == "Known month-end pattern"
    end

    test "dismissing without a reason is rejected and the Case is untouched",
         %{conn: conn, org: org} do
      case_record = investigating_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html =
        view
        |> form("#dismiss-form", %{"reason" => ""})
        |> render_submit()

      assert html =~ "reason is required"
      assert Ash.reload!(case_record, tenant: org).status == :investigating
    end
  end

  describe "closing with an Attestation" do
    defp confirmed_case(org, title) do
      {:ok, confirmed} =
        org |> investigating_case(title) |> Compliance.confirm_case(tenant: org)

      confirmed
    end

    test "closing a confirmed Case records an Attestation bound to the acting Auditor",
         %{conn: conn, org: org, user: user} do
      case_record = confirmed_case(org, "PO0042 above threshold")
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.id}/cases/#{case_record.id}")

      html = view |> element("button", "Close") |> render_click()

      assert html =~ "closed"
      assert html =~ "Attested by"
      assert html =~ to_string(user.email)

      reloaded = Ash.reload!(case_record, tenant: org) |> Ash.load!(:attestation, tenant: org)
      assert reloaded.status == :closed
      assert reloaded.attestation.auditor_id == user.id
      assert reloaded.attestation.auditor_email == to_string(user.email)
    end
  end
end
