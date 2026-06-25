defmodule Bedrock.Compliance.Ingestion do
  @moduledoc """
  Implementation of the `ingest_events` action — the seam the whole system hangs
  off. Runs the Layer-1 Deterministic Engine over a batch of normalized Odoo
  records, opening a `Case` (bundling a `HardEvidence` snapshot) for every finding
  it produces. There are two kinds of finding (ADR-0004):

    * **Rule `Violation`s** — each activated Control implements the
      `Bedrock.Compliance.Control` behaviour and sees the whole batch, so
      cross-record Controls (split-PO, duplicate invoice/vendor, 3-way match) can
      correlate records a per-record check could never see together. Activation
      parameters are fixed here for now; the per-Organization Control activation
      resource arrives in a later slice.
    * **`ConformanceDeviation`s** — each PO's actual journey is reconstructed into
      a `ProcessInstance` and checked against the canonical `Process` state
      machine. A skipped step, out-of-order activity, or receive-after-pay opens a
      Case with the offending journey as Hard Evidence.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query
  require Logger

  alias Bedrock.Compliance

  alias Bedrock.Compliance.{
    AnomalyDetection,
    Conformance,
    EventHistory,
    Normalizer,
    ProcessInstance,
    VendorBankChange
  }

  alias Bedrock.Compliance.Controls.{
    DuplicateInvoice,
    DuplicateVendor,
    SplitPo,
    ThreeWayMatch,
    ThresholdApproval
  }

  # The activated Controls and their parameters (CONTEXT.md example: "PO > 500M
  # must carry a CFO signature"). Moves to a Control activation resource later.
  @controls [
    {ThresholdApproval, [threshold: 500_000_000, approver_role: "CFO"]},
    {SplitPo, [threshold: 500_000_000, window_hours: 72]},
    {DuplicateInvoice, []},
    {DuplicateVendor, []},
    {ThreeWayMatch, [quantity_tolerance: 0, price_tolerance: 0]}
  ]

  @impl true
  def run(input, _opts, _context) do
    tenant = input.tenant

    # First gate (ADR-0011): coerce/validate against the pinned field contract and
    # pull malformed records out as a data-quality signal, so a single bad record
    # never crashes the batch nor reaches a Control that would misjudge it. Every
    # downstream phase reads only the validated subset.
    {records, quarantined} = Normalizer.normalize(input.arguments.records)
    quarantine!(quarantined, tenant)

    # Poll-only sourcing of the flagship trigger (ADR-0011): diff each polled
    # `res.partner.bank` snapshot against its last-known value in the Event History
    # and fold any synthesized `vendor_change` into the batch, so the bank-change
    # anomaly fires on stock Odoo. Runs *before* the upsert, so the diff reads the
    # prior value, not the one just polled.
    records = records ++ VendorBankChange.synthesize(records, tenant)

    # Persist the validated batch into the tenant Event History, upserted-latest by
    # the semantic key (ADR-0011) — the substrate cross-batch correlation reads.
    persist_events!(records, tenant)

    violation_cases =
      for {control, opts} <- @controls,
          window = replay_window(control, records, tenant),
          finding <- control.findings(window, opts) do
        open_case!(control, finding, tenant)
      end

    warn_unmatched_events(records)
    instances = reconstruct_process_instances!(conformance_window(records, tenant), tenant)

    conformance_cases =
      for instance <- instances,
          deviation <- Conformance.check(activity_sequence(instance)) do
        open_conformance_case!(instance, deviation, tenant)
      end

    anomaly_cases = detect_anomalies(records, tenant)

    {:ok, violation_cases ++ conformance_cases ++ anomaly_cases}
  end

  # Layer 2: score the batch against the tenant's seeded Baselines and open a Case
  # for every outlier. With no Baseline (a cold-start Organization) this finds
  # nothing — Layer 2 raises suspicion only where backfill has learned normal.
  defp detect_anomalies(records, tenant) do
    baselines = Compliance.list_baselines!(tenant: tenant)

    for detector <- AnomalyDetection.detectors(),
        window = replay_window(detector, records, tenant),
        finding <- AnomalyDetection.anomalies(detector, window, baselines) do
      open_anomaly_case!(detector, finding, tenant)
    end
  end

  # Replay a Control's or detector's cross-batch window from the Event History
  # (ADR-0011): a module declaring a `correlation/0` spec is evaluated over its
  # touched-entity window (the batch merged with the relevant recent history); one
  # that needs only the records in hand (no `correlation/0`) sees the batch alone.
  defp replay_window(module, records, tenant) do
    if function_exported?(module, :correlation, 0) do
      EventHistory.window(records, tenant, module.correlation())
    else
      records
    end
  end

  # The P2P event types that name a Purchase Order and so reconstruct a journey.
  @conformance_types [:purchase_order, :goods_receipt, :vendor_bill, :payment]

  # Replay each touched PO's *complete* journey from the Event History (ADR-0011):
  # reconstruction triggers on any event naming a `po_ref`, not on a PO record being
  # present in the batch, so a late payment whose PO synced earlier is still attached
  # and conformance-checked (#21). `:full` is entity-complete (capped at 12 months).
  defp conformance_window(records, tenant) do
    EventHistory.window(records, tenant, %{
      types: @conformance_types,
      key: &po_key/1,
      lookback: :full
    })
  end

  # The PO a record belongs to: a related event's `po_ref`, or a PO record's own id.
  defp po_key(record) do
    case Map.get(record, :po_ref) do
      nil -> if Map.get(record, :type) == :purchase_order, do: Map.get(record, :id)
      po_ref -> po_ref
    end
  end

  # Reconstruct one ProcessInstance per PO from the batch, persist its ordered
  # journey (ADR-0004), and return the in-memory instances for conformance checking.
  defp reconstruct_process_instances!(records, tenant) do
    records
    |> ProcessInstance.reconstruct()
    |> Enum.map(fn instance ->
      Compliance.create_process_instance!(
        %{po_ref: instance.po_ref, activities: instance.activities},
        tenant: tenant
      )

      instance
    end)
  end

  defp activity_sequence(instance), do: Enum.map(instance.activities, & &1.activity)

  # Upsert each keyable record into the Event History (poll/webhook of the same fact
  # collapse to one Event). A record with no derivable semantic key is not retained
  # here — it still flows through detection.
  defp persist_events!(records, tenant) do
    for record <- records, {:ok, key} <- [Normalizer.event_key(record)] do
      Compliance.upsert_event!(
        %{
          natural_key: key,
          event_type: to_string(Map.get(record, :type)),
          payload: record,
          occurred_at: Map.get(record, :occurred_at) || Map.get(record, :order_date)
        },
        tenant: tenant
      )
    end
  end

  # Persist each quarantined record as a visible, queryable data-quality signal
  # (the rest of the batch already proceeded without it).
  defp quarantine!(quarantined, tenant) do
    for %{raw: raw, reason: reason} <- quarantined do
      Compliance.create_quarantine_entry!(%{raw: raw, reason: reason}, tenant: tenant)
    end
  end

  # A P2P event that names no Purchase Order can't join any journey — surface it as
  # a data-quality signal instead of dropping it silently.
  defp warn_unmatched_events(records) do
    case ProcessInstance.unmatched_events(records) do
      [] ->
        :ok

      events ->
        Logger.warning(
          "ingest_events: #{length(events)} P2P event(s) with no po_ref skipped — " <>
            "cannot attach to a Process Instance: " <>
            Enum.map_join(events, ", ", &to_string(Map.get(&1, :type)))
        )
    end
  end

  # A Conformance Deviation opens a Case bundling the deviation and a HardEvidence
  # snapshot of the offending journey — the same shape a Violation opens, with the
  # finding's "flow" sibling in place of a `Violation`.
  defp open_conformance_case!(instance, deviation, tenant) do
    finding_type = "Conformance Deviation"
    # Episode-grained per PO + divergence kind + offending activity, so the same
    # deviation re-ingested reopens no second Case while distinct deviations on one
    # journey still each open (ADR-0011).
    finding_key = "#{instance.po_ref}|#{deviation.kind}|#{deviation.activity}"

    open_idempotent(finding_type, finding_key, tenant, fn ->
      Compliance.open_conformance_case!(
        %{
          title: "PO #{instance.po_ref} — Conformance deviation (#{deviation.kind})",
          finding_type: finding_type,
          finding_key: finding_key,
          conformance_deviation: %{
            kind: deviation.kind,
            reason: deviation.reason,
            po_ref: instance.po_ref
          },
          hard_evidence: %{snapshot: journey_snapshot(instance, deviation)}
        },
        tenant: tenant
      )
    end)
  end

  defp journey_snapshot(instance, deviation) do
    %{
      po_ref: instance.po_ref,
      deviation: deviation.kind,
      offending_activity: deviation.activity,
      journey: instance.activities
    }
  end

  # A Layer-2 Anomaly opens a Case bundling the candidate (its Anomaly Score and a
  # candidate-framed reason) and a HardEvidence snapshot — the same shape a
  # Violation opens, with the suspicion-bearing `Anomaly` in place of a `Violation`.
  defp open_anomaly_case!(detector, finding, tenant) do
    finding_type = "Anomaly: #{finding.anomaly_type}"
    finding_key = Map.get(finding, :finding_key)

    open_idempotent(finding_type, finding_key, tenant, fn ->
      Compliance.open_anomaly_case!(
        %{
          title: "#{finding.subject} — Anomaly (#{detector.detector_name()})",
          finding_type: finding_type,
          finding_key: finding_key,
          anomaly: %{
            anomaly_type: finding.anomaly_type,
            score: finding.score,
            reason: finding.reason,
            # Odoo entity ids arrive as integers; the Anomaly stores entity_ref as a string.
            entity_ref: to_string(finding.entity_ref)
          },
          hard_evidence: %{snapshot: finding.evidence}
        },
        tenant: tenant
      )
    end)
  end

  defp open_case!(control, finding, tenant) do
    finding_type = control.control_name()
    finding_key = Map.get(finding, :finding_key)

    open_idempotent(finding_type, finding_key, tenant, fn ->
      Compliance.open_case!(
        %{
          title: "#{finding.subject} — #{control.control_name()}",
          finding_type: finding_type,
          finding_key: finding_key,
          violation: %{control_name: control.control_name(), reason: finding.reason},
          hard_evidence: %{snapshot: finding.evidence}
        },
        tenant: tenant
      )
    end)
  end

  # Idempotent open (ADR-0011): a Case is unique on its `{finding_type, finding_key}`
  # Episode identity, so re-ingesting the same batch reopens nothing — and never
  # re-enqueues a weave. A finding with no key cannot be deduplicated and always
  # opens, preserving its prior single-batch behaviour.
  defp open_idempotent(finding_type, finding_key, tenant, opener) do
    case existing_case(finding_type, finding_key, tenant) do
      nil ->
        case_record = opener.()
        enqueue_weave(case_record, tenant)
        case_record

      case_record ->
        case_record
    end
  end

  defp existing_case(_finding_type, nil, _tenant), do: nil

  defp existing_case(finding_type, finding_key, tenant) do
    Compliance.Case
    |> Ash.Query.filter(finding_type == ^finding_type and finding_key == ^finding_key)
    |> Ash.read_one!(tenant: tenant)
  end

  # Hand Layer 3 off to a background job: the verdict is already committed, so a
  # slow or failing Context Weaver never blocks or alters the Case — whichever
  # finding (Violation or Conformance Deviation) opened it.
  defp enqueue_weave(case_record, tenant) do
    AshOban.run_trigger(case_record, :weave_narrative, tenant: to_tenant(tenant))
  end

  defp to_tenant(tenant) when is_binary(tenant), do: tenant
  defp to_tenant(tenant), do: Ash.ToTenant.to_tenant(tenant, Compliance.Case)
end
