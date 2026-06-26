defmodule Bedrock.Compliance.AlertPromotionTest do
  @moduledoc """
  The Alert promotion gate (ADR-0010): every finding opens a `Case` (recall), but
  only a finding clearing the gate also creates an `Alert` (precision). Driven
  through the single `ingest_events` seam with fixtures, asserting on the
  persisted `Alert`/`Case` state — never on the gate internals.
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

  test "a critical, material, unsuppressed Violation promotes to an Alert pointing at its Case",
       %{org: org, connection: connection} do
    # A PO well over the 500M CFO threshold with no CFO approval — a critical breach
    # carrying real money at risk, so it clears the promotion gate.
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
    assert alert.severity == :critical
  end

  test "a material but sub-critical Violation opens a Case but no Alert", %{
    org: org,
    connection: connection
  } do
    # A duplicated vendor bill is a :high Control (not :critical) — material, but
    # below the Severity bar the precision channel requires.
    bills = [
      %{
        type: :vendor_bill,
        id: "B1",
        vendor_id: "V1",
        invoice_number: "INV-9",
        amount_total: 90_000_000
      },
      %{
        type: :vendor_bill,
        id: "B2",
        vendor_id: "V1",
        invoice_number: "INV-9",
        amount_total: 90_000_000
      }
    ]

    assert {:ok, [_case]} = ingest(connection, bills, org)

    assert [_case] = Compliance.list_cases!(tenant: org)
    assert [] = Compliance.list_alerts!(tenant: org)
  end

  test "a critical Violation below the Materiality Floor opens a Case but no Alert" do
    # An Organization whose floor sits above this PO's total: a critical breach that
    # is nonetheless immaterial, so it stays in the recall channel only.
    org =
      Compliance.create_organization!(%{
        name: "HighFloor #{System.unique_integer([:positive])}",
        materiality_floor: Money.new(:VND, 1_000_000_000)
      })

    connection =
      Compliance.create_connection!(
        %{name: "Primary", odoo_url: "https://hf.odoo.com", credential: "ro-secret"},
        tenant: org
      )

    # Over the 500M CFO threshold (a critical Violation) but under the 1B floor.
    po = %{
      type: :purchase_order,
      id: "PO-SMALL",
      vendor_id: "V1",
      amount_total: 800_000_000,
      currency: "VND",
      order_date: ~U[2026-01-01 09:00:00Z]
    }

    assert {:ok, [_case]} = ingest(connection, [po], org)

    assert [_case] = Compliance.list_cases!(tenant: org)
    assert [] = Compliance.list_alerts!(tenant: org)
  end
end
