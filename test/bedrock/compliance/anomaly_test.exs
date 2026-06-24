defmodule Bedrock.Compliance.AnomalyTest do
  @moduledoc """
  Domain-level coverage of Layer 2 (the Anomaly Detection Engine), driven through
  the public domain interface with fixture events (no real Odoo). A historical
  batch is backfilled into per-entity `Baseline`s; subsequent events are scored
  against them, and outliers open a `Case` carrying an `Anomaly` — a candidate,
  never a `Violation`. Asserts on resulting domain state, never on private
  functions.
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

  # One vendor whose bank account changed, then was paid `window_hours` later — the
  # raw material both for seeding a Baseline and for the flagship pattern.
  defp change_then_pay(vendor_id, window_hours) do
    changed_at = ~U[2025-01-01 09:00:00Z]
    paid_at = DateTime.add(changed_at, window_hours * 3600, :second)

    [
      %{
        type: :vendor_change,
        vendor_id: vendor_id,
        field: :bank_account,
        old_value: "VN-#{vendor_id}-OLD",
        new_value: "VN-#{vendor_id}-NEW",
        occurred_at: changed_at
      },
      %{
        type: :payment,
        vendor_id: vendor_id,
        po_ref: "PO-#{vendor_id}",
        amount_total: 10_000_000,
        occurred_at: paid_at
      }
    ]
  end

  # A spread of normal change→payment windows (5–15 days) across distinct vendors.
  defp normal_history do
    [120, 168, 200, 240, 280, 300, 336, 360, 192, 264]
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {hours, i} -> change_then_pay("HV#{i}", hours) end)
  end

  defp ingest(connection, records, org),
    do: Compliance.ingest_events(connection, records, tenant: org)

  # A vendor's history of normal-sized payments (≈8–13M VND), enough samples to
  # establish a per-vendor amount Baseline.
  defp normal_payment_history(vendor_id) do
    [8, 9, 10, 11, 12, 10, 9, 11, 13, 8, 10, 12]
    |> Enum.with_index(1)
    |> Enum.map(fn {millions, i} ->
      %{
        type: :payment,
        vendor_id: vendor_id,
        po_ref: "#{vendor_id}-H#{i}",
        amount_total: millions * 1_000_000,
        occurred_at: DateTime.add(~U[2025-01-01 09:00:00Z], i * 86_400, :second)
      }
    end)
  end

  describe "backfill_baselines" do
    test "computes a per-process Baseline from historical change→payment windows", %{
      org: org,
      connection: connection
    } do
      assert {:ok, _baselines} =
               Compliance.backfill_baselines(connection, normal_history(), tenant: org)

      assert [baseline] =
               Compliance.list_baselines!(tenant: org)
               |> Enum.filter(&(&1.metric == :bank_change_to_payment_hours))

      assert baseline.entity_type == :process
      assert baseline.entity_ref == "p2p"
      # Ten distinct vendors, each contributing one change→payment window.
      assert baseline.count == 10
    end
  end

  describe "flagship: bank account changed, then paid in an unusually short window" do
    test "opens a Case carrying a candidate Anomaly with the before/after diff as Hard Evidence",
         %{org: org, connection: connection} do
      # Seed the process-wide Baseline of normal change→payment windows (5–15 days).
      assert {:ok, _} = Compliance.backfill_baselines(connection, normal_history(), tenant: org)

      # Vendor VX's bank account changed, then was paid just 2 hours later.
      fraud = [
        %{
          type: :vendor_change,
          vendor_id: "VX",
          field: :bank_account,
          old_value: "VN-LEGIT-001",
          new_value: "VN-EVIL-999",
          occurred_at: ~U[2026-02-01 09:00:00Z]
        },
        # Sub-threshold amount, so this isolates to the timing anomaly (the flagship
        # is about the short window, not the amount — see the Threshold Approval Control).
        %{
          type: :payment,
          vendor_id: "VX",
          po_ref: "PO-X",
          amount_total: 50_000_000,
          occurred_at: ~U[2026-02-01 11:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, fraud, org)

      case_record =
        Ash.load!(case_record, [:anomaly, :violation, :hard_evidence], tenant: org)

      # An Anomaly is a candidate — explicitly never a Violation.
      assert is_nil(case_record.violation)
      assert case_record.anomaly.anomaly_type == :bank_change_before_payment
      assert case_record.anomaly.entity_ref == "VX"
      assert case_record.anomaly.score >= 95
      assert case_record.anomaly.reason =~ "candidate"

      # The before/after diff (reconstructed from Odoo field-tracking) is Hard Evidence.
      diff = case_record.hard_evidence.snapshot["diff"]
      assert diff["field"] == "bank_account"
      assert diff["before"] == "VN-LEGIT-001"
      assert diff["after"] == "VN-EVIL-999"
    end

    test "a payment within the normal change→payment window opens no Anomaly", %{
      org: org,
      connection: connection
    } do
      assert {:ok, _} = Compliance.backfill_baselines(connection, normal_history(), tenant: org)

      # Bank account changed, then paid 10 days later — squarely within normal.
      benign = [
        %{
          type: :vendor_change,
          vendor_id: "VY",
          field: :bank_account,
          old_value: "VN-OLD",
          new_value: "VN-NEW",
          occurred_at: ~U[2026-02-01 09:00:00Z]
        },
        %{
          type: :payment,
          vendor_id: "VY",
          po_ref: "PO-Y",
          amount_total: 50_000_000,
          occurred_at: ~U[2026-02-11 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, benign, org)
      assert [] = Compliance.list_cases!(tenant: org)
    end
  end

  describe "generic: unusual payment amount" do
    test "a payment far larger than a vendor's normal opens a candidate Anomaly Case", %{
      org: org,
      connection: connection
    } do
      assert {:ok, _} =
               Compliance.backfill_baselines(connection, normal_payment_history("AV1"),
                 tenant: org
               )

      # A 480M payment dwarfs AV1's ≈10M normal (and stays under the 500M approval
      # threshold, so this isolates to the amount anomaly).
      big = [
        %{
          type: :payment,
          vendor_id: "AV1",
          po_ref: "PO-BIG",
          amount_total: 480_000_000,
          occurred_at: ~U[2026-03-01 09:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, big, org)

      case_record = Ash.load!(case_record, [:anomaly, :violation], tenant: org)

      assert is_nil(case_record.violation)
      assert case_record.anomaly.anomaly_type == :unusual_payment_amount
      assert case_record.anomaly.entity_ref == "AV1"
      assert case_record.anomaly.score >= 95
      assert case_record.anomaly.reason =~ "candidate"
    end

    test "scores against the seeded Baseline when the vendor id is an integer (Odoo id)", %{
      org: org,
      connection: connection
    } do
      # Odoo vendor ids are integers; the Baseline persists entity_ref as a string,
      # so live scoring must match the two regardless of the raw id type.
      assert {:ok, _} =
               Compliance.backfill_baselines(connection, normal_payment_history(42), tenant: org)

      big = [
        %{
          type: :payment,
          vendor_id: 42,
          po_ref: "PO-BIG",
          amount_total: 480_000_000,
          occurred_at: ~U[2026-03-01 09:00:00Z]
        }
      ]

      assert {:ok, [case_record]} = ingest(connection, big, org)

      case_record = Ash.load!(case_record, [:anomaly], tenant: org)

      assert case_record.anomaly.anomaly_type == :unusual_payment_amount
      assert case_record.anomaly.entity_ref == "42"
      assert case_record.anomaly.score >= 95
    end

    test "a payment of a vendor's normal size opens no Anomaly", %{
      org: org,
      connection: connection
    } do
      assert {:ok, _} =
               Compliance.backfill_baselines(connection, normal_payment_history("AV2"),
                 tenant: org
               )

      normal = [
        %{
          type: :payment,
          vendor_id: "AV2",
          po_ref: "PO-OK",
          amount_total: 10_000_000,
          occurred_at: ~U[2026-03-01 09:00:00Z]
        }
      ]

      assert {:ok, []} = ingest(connection, normal, org)
      assert [] = Compliance.list_cases!(tenant: org)
    end
  end
end
