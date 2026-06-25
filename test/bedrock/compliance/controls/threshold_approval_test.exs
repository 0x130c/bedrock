defmodule Bedrock.Compliance.Controls.ThresholdApprovalTest do
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Controls.ThresholdApproval
  alias Bedrock.Compliance.Normalizer

  # Coerce through the real normalizer, so the Control reads the same shape
  # (`amount_total` as `Money`) the ingestion seam feeds it.
  defp po(attrs) do
    {[coerced], []} = Normalizer.normalize([Map.put(attrs, :type, :purchase_order)])
    coerced
  end

  describe "evaluate/2" do
    test "a PO above the threshold lacking the required approver role is a violation naming the control" do
      po =
        po(%{
          id: "PO0042",
          amount_total: 750_000_000,
          currency: "VND",
          approvals: [%{role: "manager"}]
        })

      assert {:violation, reason} =
               ThresholdApproval.evaluate(po, threshold: 500_000_000, approver_role: "CFO")

      assert reason =~ "Threshold Approval"
      assert reason =~ "PO0042"
      assert reason =~ "CFO"
    end

    test "a PO above the threshold carrying the required approver role is compliant" do
      po =
        po(%{
          id: "PO0043",
          amount_total: 750_000_000,
          currency: "VND",
          approvals: [%{role: "manager"}, %{role: "CFO"}]
        })

      assert :ok =
               ThresholdApproval.evaluate(po, threshold: 500_000_000, approver_role: "CFO")
    end

    test "a PO at or below the threshold is compliant even without the approver" do
      below = po(%{id: "PO0044", amount_total: 499_999_999, currency: "VND", approvals: []})
      at = po(%{id: "PO0045", amount_total: 500_000_000, currency: "VND", approvals: []})

      assert :ok = ThresholdApproval.evaluate(below, threshold: 500_000_000, approver_role: "CFO")
      assert :ok = ThresholdApproval.evaluate(at, threshold: 500_000_000, approver_role: "CFO")
    end
  end
end
