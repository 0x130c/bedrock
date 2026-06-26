defmodule Bedrock.Compliance.AlertDeliveryTest do
  @moduledoc """
  Alert delivery via a swappable port (ADR-0002, ADR-0010). A promoted Alert is
  delivered through `Bedrock.Compliance.AlertDelivery`, whose adapter is configured
  per-environment; tests inject a recording adapter and assert on the persisted
  Alert and what the adapter captured — never a real Slack/Telegram/SMS/webhook call.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance
  alias Bedrock.Test.RecordingAlertAdapter

  setup do
    RecordingAlertAdapter.reset()

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

  test "a promoted Alert is delivered through the swappable port and marked delivered", %{
    org: org,
    connection: connection
  } do
    po = %{
      type: :purchase_order,
      id: "PO-CRIT",
      vendor_id: "V1",
      amount_total: 800_000_000,
      currency: "VND",
      order_date: ~U[2026-01-01 09:00:00Z]
    }

    assert {:ok, [case_record]} = ingest(connection, [po], org)

    assert [alert] = Compliance.list_alerts!(tenant: org)
    assert alert.case_id == case_record.id
    assert alert.delivery_status == :delivered
    refute is_nil(alert.delivered_at)

    # The recording adapter captured exactly this Alert — and no real channel was hit.
    assert [delivered] = RecordingAlertAdapter.deliveries()
    assert delivered.id == alert.id
  end

  test "a finding that stays Case-only delivers nothing", %{org: org, connection: connection} do
    # A sub-critical (and immaterial) finding never alerts, so nothing is delivered.
    vendors = [
      %{type: :vendor, id: "V1", name: "Acme", tax_id: "0101234567"},
      %{type: :vendor, id: "V2", name: "Acme Co", tax_id: "0101234567"}
    ]

    assert {:ok, [_case]} = ingest(connection, vendors, org)

    assert [] = Compliance.list_alerts!(tenant: org)
    assert [] = RecordingAlertAdapter.deliveries()
  end
end
