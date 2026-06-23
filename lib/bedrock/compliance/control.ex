defmodule Bedrock.Compliance.Control do
  @moduledoc """
  The contract every deterministic Layer-1 Control implements.

  A Control is a pure, parameterized check over a batch of normalized Odoo
  records. It selects the record types it cares about, evaluates the rule, and
  returns one `finding` per breach — naming nothing it cannot stand behind. No
  database, no AI; the source of truth for whether a rule is breached lives in
  the Control and nowhere else.

  Operating over the whole batch (not one record at a time) is what lets
  cross-record Controls — split-PO, duplicate invoice/vendor, 3-way match —
  correlate records that a per-record signature could never see together.

  A `finding` is the verdict-bearing payload the ingestion seam turns into a
  `Case`:

    * `:reason` — a human-readable explanation naming the Control and why it
      breached (`Violation.reason`).
    * `:evidence` — a snapshot of the offending record(s) (`HardEvidence.snapshot`).
    * `:subject` — a short label for the offending object, used in the Case title.
  """

  @type normalized_record :: map()
  @type finding :: %{reason: String.t(), evidence: map(), subject: String.t()}

  @doc "The human-readable name of this Control, used in Violation reasons and titles."
  @callback control_name() :: String.t()

  @doc "Evaluate the activated Control over a batch of records, returning one finding per breach."
  @callback findings(records :: [normalized_record()], opts :: keyword()) :: [finding()]
end
