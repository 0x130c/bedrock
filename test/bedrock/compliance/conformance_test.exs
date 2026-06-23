defmodule Bedrock.Compliance.ConformanceTest do
  @moduledoc """
  Unit coverage of the pure Layer-1 conformance checker: it walks a Process
  Instance's ordered activities against the pre-built P2P `Process` state machine
  and returns one Conformance Deviation per divergence. No database, no AI — the
  source of truth for whether a journey conforms lives here and the `Process`.
  """
  use ExUnit.Case, async: true

  alias Bedrock.Compliance.Conformance

  describe "check/1" do
    test "a clean happy-path journey produces no deviations" do
      activities = [:approve, :receive_goods, :bill, :pay]

      assert Conformance.check(activities) == []
    end

    test "a journey that skips approval raises a skipped-step deviation naming the skip" do
      activities = [:receive_goods, :bill, :pay]

      assert [deviation] = Conformance.check(activities)
      assert deviation.kind == :skipped_step
      assert deviation.reason =~ "approval"
    end

    test "goods received after the PO is paid raises a receive-after-pay deviation" do
      activities = [:approve, :receive_goods, :bill, :pay, :receive_goods]

      assert [deviation] = Conformance.check(activities)
      assert deviation.kind == :receive_after_pay
      assert deviation.reason =~ "paid"
    end

    test "an approval recorded after billing raises an out-of-order deviation" do
      activities = [:approve, :receive_goods, :bill, :approve]

      assert [deviation] = Conformance.check(activities)
      assert deviation.kind == :out_of_order
      assert deviation.reason =~ "out of order"
    end
  end
end
