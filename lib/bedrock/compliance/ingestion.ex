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

  alias Bedrock.Compliance
  alias Bedrock.Compliance.{Conformance, ProcessInstance}

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
    records = input.arguments.records

    violation_cases =
      for {control, opts} <- @controls,
          finding <- control.findings(records, opts) do
        open_case!(control, finding, tenant)
      end

    instances = reconstruct_process_instances!(records, tenant)

    conformance_cases =
      for instance <- instances,
          deviation <- Conformance.check(activity_sequence(instance)) do
        open_conformance_case!(instance, deviation, tenant)
      end

    {:ok, violation_cases ++ conformance_cases}
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

  # A Conformance Deviation opens a Case bundling the deviation and a HardEvidence
  # snapshot of the offending journey — the same shape a Violation opens, with the
  # finding's "flow" sibling in place of a `Violation`.
  defp open_conformance_case!(instance, deviation, tenant) do
    Compliance.open_conformance_case!(
      %{
        title: "PO #{instance.po_ref} — Conformance deviation (#{deviation.kind})",
        conformance_deviation: %{
          kind: deviation.kind,
          reason: deviation.reason,
          po_ref: instance.po_ref
        },
        hard_evidence: %{snapshot: journey_snapshot(instance, deviation)}
      },
      tenant: tenant
    )
  end

  defp journey_snapshot(instance, deviation) do
    %{
      po_ref: instance.po_ref,
      deviation: deviation.kind,
      offending_activity: deviation.activity,
      journey:
        Enum.map(instance.activities, fn activity ->
          %{activity: activity.activity, occurred_at: activity.occurred_at}
        end)
    }
  end

  defp open_case!(control, finding, tenant) do
    case_record =
      Compliance.open_case!(
        %{
          title: "#{finding.subject} — #{control.control_name()}",
          violation: %{control_name: control.control_name(), reason: finding.reason},
          hard_evidence: %{snapshot: finding.evidence}
        },
        tenant: tenant
      )

    # Hand Layer 3 off to a background job: the verdict is already committed, so a
    # slow or failing Context Weaver never blocks or alters this Case.
    AshOban.run_trigger(case_record, :weave_narrative, tenant: to_tenant(tenant))

    case_record
  end

  defp to_tenant(tenant) when is_binary(tenant), do: tenant
  defp to_tenant(tenant), do: Ash.ToTenant.to_tenant(tenant, Compliance.Case)
end
