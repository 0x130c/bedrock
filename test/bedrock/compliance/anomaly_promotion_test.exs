defmodule Bedrock.Compliance.AnomalyPromotionTest do
  @moduledoc """
  Baseline maturity in the promotion gate (ADR-0010): a Layer-2 Anomaly opens a
  Case as soon as it is a candidate, but only promotes to an Alert once the
  Baseline behind its score is *mature* — enough history to trust the precision
  channel. Driven through `ingest_events`.
  """
  use Bedrock.DataCase, async: false

  alias Bedrock.Compliance
  alias Bedrock.Compliance.PromotionGate

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

  # `n` normal ≈10M payments for one vendor — the raw material to backfill a
  # per-vendor payment-amount Baseline of a chosen sample count.
  defp normal_payments(vendor_id, n) do
    for i <- 1..n do
      %{
        type: :payment,
        vendor_id: vendor_id,
        po_ref: "#{vendor_id}-H#{i}",
        amount_total: (9 + rem(i, 5)) * 1_000_000,
        occurred_at: DateTime.add(~U[2025-01-01 09:00:00Z], i * 86_400, :second)
      }
    end
  end

  defp big_payment(vendor_id) do
    %{
      type: :payment,
      vendor_id: vendor_id,
      po_ref: "PO-BIG",
      amount_total: 480_000_000,
      occurred_at: ~U[2026-03-01 09:00:00Z]
    }
  end

  test "an Anomaly on a mature Baseline promotes to an Alert", %{org: org, connection: connection} do
    mature = PromotionGate.mature_baseline_count() + 5

    assert {:ok, _} =
             Compliance.backfill_baselines(connection, normal_payments("AV1", mature),
               tenant: org
             )

    assert {:ok, [case_record]} = ingest(connection, [big_payment("AV1")], org)

    assert [alert] = Compliance.list_alerts!(tenant: org)
    assert alert.case_id == case_record.id
  end

  test "an Anomaly on an immature Baseline opens a Case but no Alert", %{
    org: org,
    connection: connection
  } do
    immature = PromotionGate.mature_baseline_count() - 1

    assert {:ok, _} =
             Compliance.backfill_baselines(connection, normal_payments("AV2", immature),
               tenant: org
             )

    assert {:ok, [_case]} = ingest(connection, [big_payment("AV2")], org)

    assert [_case] = Compliance.list_cases!(tenant: org)
    assert [] = Compliance.list_alerts!(tenant: org)
  end
end
