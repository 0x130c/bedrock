defmodule Bedrock.Compliance.CaseLifecycleTest do
  @moduledoc """
  The `Case` lifecycle state machine (ADR-0008) and the Attestation requirement on
  close (ADR-0009). Drives the transitions through the domain code interface with a
  tenant and — where identity matters — an actor.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance

  setup do
    org =
      Compliance.create_organization!(%{name: "Acme #{System.unique_integer([:positive])}"})

    %{org: org}
  end

  defp open_case(org) do
    Compliance.open_case!(
      %{
        title: "PO0042 above threshold without CFO approval",
        violation: %{control_name: "Threshold Approval", reason: "PO0042 missing CFO"},
        hard_evidence: %{snapshot: %{"id" => "PO0042"}}
      },
      tenant: org
    )
  end

  describe "lifecycle transitions" do
    test "a freshly opened Case starts in :open and can be triaged", %{org: org} do
      case_record = open_case(org)
      assert case_record.status == :open

      assert {:ok, triaged} = Compliance.triage_case(case_record, tenant: org)
      assert triaged.status == :triaged
    end

    test "a triaged Case can be moved into investigating", %{org: org} do
      {:ok, triaged} = open_case(org) |> Compliance.triage_case(tenant: org)

      assert {:ok, investigating} = Compliance.investigate_case(triaged, tenant: org)
      assert investigating.status == :investigating
    end

    test "a transition that skips a state is rejected (open cannot jump to investigating)",
         %{org: org} do
      case_record = open_case(org)

      assert {:error, error} = Compliance.investigate_case(case_record, tenant: org)
      assert Exception.message(error) =~ "transition"
      # The Case is untouched — it stays in :open.
      assert Ash.reload!(case_record, tenant: org).status == :open
    end
  end

  describe "decisions from investigating" do
    defp investigating_case(org) do
      {:ok, case_record} =
        open_case(org)
        |> Compliance.triage_case(tenant: org)

      {:ok, investigating} = Compliance.investigate_case(case_record, tenant: org)
      investigating
    end

    test "an investigating Case can be confirmed", %{org: org} do
      assert {:ok, confirmed} =
               Compliance.confirm_case(investigating_case(org), tenant: org)

      assert confirmed.status == :confirmed
    end

    test "an investigating Case can be marked accepted_risk", %{org: org} do
      assert {:ok, accepted} =
               Compliance.accept_risk_case(investigating_case(org), tenant: org)

      assert accepted.status == :accepted_risk
    end

    test "dismissing an investigating Case records the reason (feeds Suppression Rules)",
         %{org: org} do
      assert {:ok, dismissed} =
               Compliance.dismiss_case(
                 investigating_case(org),
                 %{reason: "Known month-end pattern"},
                 tenant: org
               )

      assert dismissed.status == :dismissed
      assert dismissed.dismissal_reason == "Known month-end pattern"
    end

    test "dismissing without a reason is rejected", %{org: org} do
      case_record = investigating_case(org)

      assert {:error, error} = Compliance.dismiss_case(case_record, %{}, tenant: org)
      assert %Ash.Error.Invalid{} = error

      # The Case is untouched — it stays in :investigating.
      assert Ash.reload!(case_record, tenant: org).status == :investigating
    end
  end

  describe "closing records an Attestation (ADR-0009)" do
    defp confirmed_case(org) do
      {:ok, confirmed} = Compliance.confirm_case(investigating_case(org), tenant: org)
      confirmed
    end

    defp auditor do
      %Bedrock.Accounts.User{id: Ash.UUID.generate(), email: "auditor@acme.test"}
    end

    test "closing a Case records an Attestation bound to the acting Auditor", %{org: org} do
      auditor = auditor()

      assert {:ok, closed} =
               Compliance.close_case(confirmed_case(org), actor: auditor, tenant: org)

      assert closed.status == :closed

      closed = Ash.load!(closed, :attestation, actor: auditor, tenant: org)
      assert closed.attestation.auditor_id == auditor.id
      assert closed.attestation.auditor_email == "auditor@acme.test"
      assert %DateTime{} = closed.attestation.attested_at
    end

    test "closing without an actor (no Attestation) is rejected", %{org: org} do
      confirmed = confirmed_case(org)

      assert {:error, error} = Compliance.close_case(confirmed, tenant: org)
      assert Exception.message(error) =~ "Attestation"

      # The Case is not closed and no Attestation was recorded.
      reloaded = Ash.reload!(confirmed, tenant: org) |> Ash.load!(:attestation, tenant: org)
      assert reloaded.status == :confirmed
      assert is_nil(reloaded.attestation)
    end

    test "a closed Case can be exported", %{org: org} do
      auditor = auditor()
      {:ok, closed} = Compliance.close_case(confirmed_case(org), actor: auditor, tenant: org)

      assert {:ok, exported} = Compliance.export_case(closed, tenant: org)
      assert exported.status == :exported
    end
  end
end
