defmodule Bedrock.Compliance.IngestEventHistoryTest do
  @moduledoc """
  Regression coverage for the PR-A Event History substrate (ADR-0011): every
  normalized Event is upserted into the tenant-scoped store by a *semantic* natural
  key, so the same real-world fact arriving via poll and via webhook deduplicates to
  one Event. Driven through the single `ingest_events` seam, asserting on resulting
  domain state.
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

  describe "Event History" do
    test "normalized Events are persisted, keyed by semantic identity", %{
      org: org,
      connection: connection
    } do
      batch = [
        %{type: :vendor, id: "V1", name: "Acme", tax_id: "T1"},
        %{type: :purchase_order, id: "PO1", amount_total: 100_000_000, currency: "VND"}
      ]

      assert {:ok, _} = ingest(connection, batch, org)

      events = Compliance.list_events!(tenant: org)
      keys = Enum.map(events, & &1.natural_key)
      assert "vendor:V1" in keys
      assert "purchase_order:PO1" in keys
    end

    test "poll then webhook of the same fact yields one Event (upsert-latest)", %{
      org: org,
      connection: connection
    } do
      poll = [%{type: :vendor, id: "V1", name: "Acme", tax_id: "T1"}]
      webhook = [%{type: :vendor, id: "V1", name: "Acme Updated", tax_id: "T1"}]

      assert {:ok, _} = ingest(connection, poll, org)
      assert {:ok, _} = ingest(connection, webhook, org)

      assert [event] = Compliance.list_events!(tenant: org)
      assert event.natural_key == "vendor:V1"
      # Upsert-latest: the webhook's fresher payload replaced the poll's in place.
      assert event.payload["name"] == "Acme Updated"
    end

    test "a vendor field-change is keyed by {vendor_id, field, occurred_at}", %{
      org: org,
      connection: connection
    } do
      change = [
        %{
          type: :vendor_change,
          vendor_id: "V1",
          field: :bank_account,
          old_value: "VN-OLD",
          new_value: "VN-NEW",
          occurred_at: ~U[2026-01-01 09:00:00Z]
        }
      ]

      assert {:ok, _} = ingest(connection, change, org)

      assert [event] = Compliance.list_events!(tenant: org)
      assert event.natural_key =~ "V1"
      assert event.natural_key =~ "bank_account"
    end
  end
end
