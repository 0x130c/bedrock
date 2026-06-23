defmodule Bedrock.Compliance.Conformance do
  @moduledoc """
  The pure Layer-1 conformance checker. Walks a `ProcessInstance`'s ordered
  activities against the canonical `Process` state machine and returns one
  Conformance Deviation per divergence. No database, no AI; the source of truth
  for whether a journey conforms lives here and in the `Process`.

  At each activity the checker either advances along the `Process` (legal) or
  records a deviation, classified by where the activity belongs relative to where
  the journey currently is:

    * `:skipped_step` — a *forward* jump: the activity needs prerequisites the
      journey has not reached (e.g. receiving goods on a PO that was never
      approved). The checker advances optimistically past the gap so it can find
      further deviations.
    * `:out_of_order` — a *backward* step: an activity recorded after the journey
      already moved past where it belongs (e.g. a late approval after billing).
    * `:receive_after_pay` — the named backward case of receiving goods once the
      PO has already been paid.
  """
  alias Bedrock.Compliance.Process

  @labels %{
    approve: "approval",
    receive_goods: "goods receipt",
    bill: "vendor bill",
    pay: "payment"
  }

  @doc """
  Walk `activities` (an ordered list of activity atoms) against the `Process`,
  returning the deviations in the order they occur (`[]` when the journey
  conforms).
  """
  def check(activities) do
    {deviations, _state} =
      Enum.reduce(activities, {[], Process.initial_state()}, fn activity, {deviations, state} ->
        case Process.advance(state, activity) do
          {:ok, next_state} ->
            {deviations, next_state}

          :error ->
            deviation = classify(state, activity)
            {[deviation | deviations], advance_past(state, activity)}
        end
      end)

    Enum.reverse(deviations)
  end

  defp classify(state, activity) do
    {:ok, from_state, _to_state} = Process.edge(activity)

    cond do
      activity == :receive_goods and Process.rank(state) >= Process.rank(:paid) ->
        receive_after_pay(state)

      Process.rank(state) < Process.rank(from_state) ->
        skipped_step(state, activity, from_state)

      true ->
        out_of_order(state, activity)
    end
  end

  defp skipped_step(state, activity, from_state) do
    skipped = skipped_between(state, from_state)

    %{
      kind: :skipped_step,
      activity: activity,
      reason:
        "Process Instance recorded #{label(activity)} without first completing " <>
          "#{Enum.map_join(skipped, ", ", &label/1)}."
    }
  end

  defp out_of_order(state, activity) do
    %{
      kind: :out_of_order,
      activity: activity,
      reason:
        "Process Instance recorded #{label(activity)} out of order, after the journey had " <>
          "already reached #{label_state(state)}."
    }
  end

  defp receive_after_pay(state) do
    %{
      kind: :receive_after_pay,
      activity: :receive_goods,
      reason:
        "Process Instance recorded a goods receipt after the Purchase Order was already paid " <>
          "(journey had reached #{label_state(state)})."
    }
  end

  # Forward jumps advance the journey to the activity's canonical landing state so
  # later activities are judged from there; backward steps leave the journey put.
  defp advance_past(state, activity) do
    {:ok, from_state, to_state} = Process.edge(activity)

    if Process.rank(state) < Process.rank(from_state), do: to_state, else: state
  end

  # The activities whose landing state sits in the gap (state, from_state] — i.e.
  # the steps a forward jump skipped over.
  defp skipped_between(state, from_state) do
    low = Process.rank(state)
    high = Process.rank(from_state)

    Enum.filter(Process.activities(), fn activity ->
      {:ok, _from, to_state} = Process.edge(activity)
      Process.rank(to_state) > low and Process.rank(to_state) <= high
    end)
  end

  defp label(activity), do: Map.fetch!(@labels, activity)

  defp label_state(state) do
    case Enum.find(Process.activities(), fn activity ->
           {:ok, _from, to_state} = Process.edge(activity)
           to_state == state
         end) do
      nil -> to_string(state)
      activity -> label(activity)
    end
  end
end
