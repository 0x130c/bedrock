defmodule Bedrock.Compliance.AlertPrecisionTest do
  @moduledoc """
  Per-Control Alert precision and self-tuning demotion (ADR-0010). An Alert's
  outcome — whether the Case it pointed at was actioned (confirmed / accepted-risk)
  or dismissed — is tracked per Control, and a Control whose precision falls below
  target auto-demotes to Case-only. Driven through `ingest_events` and the Case
  lifecycle.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance
  alias Bedrock.Compliance.AlertPrecision

  setup do
    org =
      Compliance.create_organization!(%{name: "Acme #{System.unique_integer([:positive])}"})

    connection =
      Compliance.create_connection!(
        %{name: "Primary", odoo_url: "https://acme.odoo.com", credential: "ro-secret"},
        tenant: org
      )

    %{org: org, connection: connection}
  end

  defp ingest(connection, records, org),
    do: Compliance.ingest_events(connection, records, tenant: org)

  defp critical_po(id) do
    %{
      type: :purchase_order,
      id: id,
      vendor_id: "V1",
      amount_total: 800_000_000,
      currency: "VND",
      order_date: ~U[2026-01-01 09:00:00Z]
    }
  end

  # Ingest a critical PO and walk its Case to :investigating, ready to resolve.
  defp investigating_alerted_case(connection, org, id) do
    {:ok, [case_record]} = ingest(connection, [critical_po(id)], org)
    {:ok, case_record} = Compliance.triage_case(case_record, tenant: org)
    {:ok, case_record} = Compliance.investigate_case(case_record, tenant: org)
    case_record
  end

  test "confirming an alerted Case counts as an actioned Alert for its Control", %{
    org: org,
    connection: connection
  } do
    case_record = investigating_alerted_case(connection, org, "PO-A")
    assert [_alert] = Compliance.list_alerts!(tenant: org)

    {:ok, _confirmed} = Compliance.confirm_case(case_record, tenant: org)

    assert {:ok, stat} = Compliance.get_control_alert_stat("Threshold Approval", tenant: org)
    assert stat.resolved_count == 1
    assert stat.actioned_count == 1
  end

  test "dismissing an alerted Case counts against its Control's precision", %{
    org: org,
    connection: connection
  } do
    case_record = investigating_alerted_case(connection, org, "PO-B")

    {:ok, _dismissed} =
      Compliance.dismiss_case(case_record, %{reason: "real but already handled"}, tenant: org)

    assert {:ok, stat} = Compliance.get_control_alert_stat("Threshold Approval", tenant: org)
    assert stat.resolved_count == 1
    assert stat.actioned_count == 0
  end

  defp critical_po_for(id, vendor_id) do
    %{
      type: :purchase_order,
      id: id,
      vendor_id: vendor_id,
      amount_total: 800_000_000,
      currency: "VND",
      order_date: ~U[2026-01-01 09:00:00Z]
    }
  end

  test "a Control whose Alerts are mostly dismissed auto-demotes to Case-only", %{
    org: org,
    connection: connection
  } do
    # Resolve enough alerted Cases — all dismissed, so precision is 0 — to cross the
    # demotion bar. Each PO is to a distinct vendor so none cluster as a split-PO.
    n = AlertPrecision.min_resolved_for_demotion()

    for i <- 1..n do
      {:ok, [case_record]} = ingest(connection, [critical_po_for("PO-#{i}", "V#{i}")], org)
      {:ok, case_record} = Compliance.triage_case(case_record, tenant: org)
      {:ok, case_record} = Compliance.investigate_case(case_record, tenant: org)
      {:ok, _} = Compliance.dismiss_case(case_record, %{reason: "noise"}, tenant: org)
    end

    assert {:ok, stat} = Compliance.get_control_alert_stat("Threshold Approval", tenant: org)
    refute is_nil(stat.demoted_at)

    alerts_before = length(Compliance.list_alerts!(tenant: org))

    # A fresh, otherwise-promotable finding from the demoted Control now opens a Case
    # but no Alert.
    {:ok, [case4]} = ingest(connection, [critical_po_for("PO-LAST", "VLAST")], org)

    assert length(Compliance.list_alerts!(tenant: org)) == alerts_before
    assert is_nil(Ash.load!(case4, [:alert], tenant: org).alert)
  end
end
