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

  Monotonic-safe (ADR-0011): only deviations stable under future appends are
  emitted. Ordering and forbidden-step deviations (`:out_of_order`,
  `:receive_after_pay`) are returned immediately — no later event can make a
  backward step legal. An *omission* (`:skipped_step` — an activity that jumped a
  missing prerequisite) is held back until the Process Instance reaches a *terminal*
  state, because under the incremental poller the missing step may still arrive
  out-of-order in a later batch; an in-flight journey is not yet evidence of an
  omission. Nothing is ever retracted.
  """
  def check(activities) do
    {deviations, final_state} =
      Enum.reduce(activities, {[], Process.initial_state()}, fn activity, {deviations, state} ->
        case Process.advance(state, activity) do
          {:ok, next_state} ->
            {deviations, next_state}

          :error ->
            deviation = classify(state, activity)
            {[deviation | deviations], advance_past(state, activity)}
        end
      end)

    deviations
    |> Enum.reverse()
    |> monotonic_safe(final_state)
  end

  # Omissions are only stable — never retractable by a future append — once the
  # journey is terminal; until then, suppress them and keep only the ordering /
  # forbidden-step deviations that no later event can legalize.
  defp monotonic_safe(deviations, final_state) do
    if terminal?(final_state), do: deviations, else: Enum.reject(deviations, &omission?/1)
  end

  defp terminal?(state), do: Process.rank(state) >= Process.rank(Process.final_state())

  defp omission?(%{kind: :skipped_step}), do: true
  defp omission?(_deviation), do: false

  defp classify(state, activity) do
    {:ok, from_state, _to_state} = Process.edge(activity)

    cond do
      receive_after_pay?(state, activity) ->
        receive_after_pay(state)

      Process.rank(state) < Process.rank(from_state) ->
        skipped_step(state, activity, from_state)

      true ->
        out_of_order(state, activity)
    end
  end

  # The named backward case: the goods-receipt activity (a Process landmark) once
  # the journey has already reached the terminal state. Both ends are read from
  # the Process, so reordering the model keeps this in step with every other branch.
  defp receive_after_pay?(state, activity) do
    activity == Process.goods_receipt_activity() and
      Process.rank(state) >= Process.rank(Process.final_state())
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
    activity = Process.goods_receipt_activity()

    %{
      kind: :receive_after_pay,
      activity: activity,
      reason:
        "Process Instance recorded #{label(activity)} after the journey had already reached " <>
          "#{label_state(state)} — a receipt logged post-payment."
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
