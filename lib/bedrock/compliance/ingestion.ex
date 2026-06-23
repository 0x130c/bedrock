defmodule Bedrock.Compliance.Ingestion do
  @moduledoc """
  Implementation of the `ingest_events` action — the seam the whole system hangs
  off. Runs the Layer-1 Deterministic Engine over a batch of normalized Odoo
  records and, for each breach, opens a `Case` bundling the `Violation` and a
  `HardEvidence` snapshot of the offending record.

  Slice 1 runs exactly one activated Control with fixed parameters. The
  parameterized Control library and per-Organization activation arrive in later
  slices; the Control logic itself already takes its parameters
  (`Bedrock.Compliance.Controls.ThresholdApproval`).
  """
  use Ash.Resource.Actions.Implementation

  alias Bedrock.Compliance
  alias Bedrock.Compliance.Controls.ThresholdApproval

  # Activated Control parameters for Slice 1 (CONTEXT.md example: "PO > 500M must
  # carry a CFO signature"). Moves to a Control activation resource in a later slice.
  @threshold 500_000_000
  @approver_role "CFO"

  @impl true
  def run(input, _opts, _context) do
    tenant = input.tenant

    cases =
      input.arguments.records
      |> Enum.flat_map(fn record ->
        case ThresholdApproval.evaluate(record,
               threshold: @threshold,
               approver_role: @approver_role
             ) do
          {:violation, reason} -> [open_case!(record, reason, tenant)]
          :ok -> []
        end
      end)

    {:ok, cases}
  end

  defp open_case!(record, reason, tenant) do
    case_record =
      Compliance.open_case!(
        %{
          title: "PO #{record[:id]} — #{ThresholdApproval.control_name()}",
          violation: %{control_name: ThresholdApproval.control_name(), reason: reason},
          hard_evidence: %{snapshot: record}
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
