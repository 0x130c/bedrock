defmodule Bedrock.Compliance.Ingestion do
  @moduledoc """
  Implementation of the `ingest_events` action — the seam the whole system hangs
  off. Runs the Layer-1 Deterministic Engine over a batch of normalized Odoo
  records and, for each breach, opens a `Case` bundling the `Violation` and a
  `HardEvidence` snapshot of the offending record(s).

  Each activated Control implements the `Bedrock.Compliance.Control` behaviour and
  sees the whole batch, so cross-record Controls (split-PO, duplicate
  invoice/vendor, 3-way match) can correlate records a per-record check could
  never see together. Activation parameters are fixed here for now; the
  per-Organization Control activation resource arrives in a later slice.
  """
  use Ash.Resource.Actions.Implementation

  alias Bedrock.Compliance

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

    cases =
      for {control, opts} <- @controls,
          finding <- control.findings(records, opts) do
        open_case!(control, finding, tenant)
      end

    {:ok, cases}
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
