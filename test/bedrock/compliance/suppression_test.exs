defmodule Bedrock.Compliance.SuppressionTest do
  @moduledoc """
  Suppression Rules (ADR-0010): a known-good pattern marked as expected stops a
  matching finding from promoting to an Alert, while the finding still opens a
  Case (recall is never sacrificed). Driven through `ingest_events`.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance

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

  test "a finding matching a Suppression Rule opens a Case but no Alert", %{
    org: org,
    connection: connection
  } do
    # Mark this Control x subject as a known-good pattern: it must not interrupt.
    Compliance.create_suppression_rule!(
      %{
        control_name: "Threshold Approval",
        subject: "PO PO-CRIT",
        reason: "approved out-of-band — expected"
      },
      tenant: org
    )

    assert {:ok, [_case]} = ingest(connection, [critical_po("PO-CRIT")], org)

    assert [_case] = Compliance.list_cases!(tenant: org)
    assert [] = Compliance.list_alerts!(tenant: org)
  end

  test "a Suppression Rule for a different subject does not block the Alert", %{
    org: org,
    connection: connection
  } do
    # An unrelated suppression must not silence this finding.
    Compliance.create_suppression_rule!(
      %{control_name: "Threshold Approval", subject: "PO OTHER", reason: "expected"},
      tenant: org
    )

    assert {:ok, [_case]} = ingest(connection, [critical_po("PO-CRIT")], org)

    assert [_alert] = Compliance.list_alerts!(tenant: org)
  end

  defp split_po(id, vendor_id, amount, at) do
    %{type: :purchase_order, id: id, vendor_id: vendor_id, amount_total: amount, order_date: at}
  end

  test "dismissing a Case as known-good suppresses the vendor's later Alerts", %{
    org: org,
    connection: connection
  } do
    # A split-PO attempt for vendor V1 → one Case in the recall channel and one Alert.
    attempt1 = [
      split_po("PO1", "V1", 300_000_000, ~U[2026-01-01 09:00:00Z]),
      split_po("PO2", "V1", 300_000_000, ~U[2026-01-02 09:00:00Z])
    ]

    assert {:ok, [case1]} = ingest(connection, attempt1, org)
    assert [_alert] = Compliance.list_alerts!(tenant: org)

    # The Auditor reviews and dismisses it as a known-good, expected pattern,
    # choosing to suppress future Alerts on this vendor's split-PO findings.
    {:ok, case1} = Compliance.triage_case(case1, tenant: org)
    {:ok, case1} = Compliance.investigate_case(case1, tenant: org)

    {:ok, _dismissed} =
      Compliance.dismiss_case(
        case1,
        %{reason: "month-end clustering — expected", suppress?: true},
        tenant: org
      )

    # That dismissal fed a Suppression Rule scoped to this Control x subject.
    assert [rule] = Compliance.list_suppression_rules!(tenant: org)
    assert rule.control_name == "Split PO"
    assert rule.subject == "Vendor V1"

    # A later, distinct split attempt for the same vendor still opens a Case (recall),
    # but is silenced in the precision channel — no second Alert.
    attempt2 = [
      split_po("PO3", "V1", 350_000_000, ~U[2026-01-20 09:00:00Z]),
      split_po("PO4", "V1", 350_000_000, ~U[2026-01-21 09:00:00Z])
    ]

    assert {:ok, [_case2]} = ingest(connection, attempt2, org)

    assert [_still_only_one] = Compliance.list_alerts!(tenant: org)
  end
end
