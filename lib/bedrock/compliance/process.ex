defmodule Bedrock.Compliance.Process do
  @moduledoc """
  The pre-built, opinionated P2P `Process` — the expected shape of a Purchase
  Order's journey, encoded as an `ash_state_machine` (ADR-0004). Customers do
  *not* author it in v1; there is exactly one canonical model and it is never
  persisted, so this resource carries no data layer. Its transition table is the
  oracle the pure `Bedrock.Compliance.Conformance` checker reads to decide whether
  a reconstructed `ProcessInstance` conforms.

  The full business process is PR → PO → approval → Goods Receipt → Vendor Bill →
  3-way match → Payment. This machine models the *event-observable* spine that
  Bedrock reconstructs from Odoo — PO (the anchor, the `:created` initial state) →
  approval → Goods Receipt → Vendor Bill → Payment. Purchase Requisitions are not
  yet ingested, and the 3-way match is enforced by its own deterministic Control
  (a `Violation`), so neither appears as a conformance transition here.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:created]
    default_initial_state :created

    transitions do
      transition :approve, from: :created, to: :approved
      transition :receive_goods, from: :approved, to: :goods_received
      transition :bill, from: :goods_received, to: :billed
      transition :pay, from: :billed, to: :paid
    end
  end

  # The transition actions exist only to satisfy the state-machine verifier; the
  # Process is never instantiated or driven, only its transition table is read.
  actions do
    defaults [:read]

    update :approve, do: nil
    update :receive_goods, do: nil
    update :bill, do: nil
    update :pay, do: nil
  end

  attributes do
    uuid_v7_primary_key :id
  end

  @doc "The state every reconstructed journey starts from (a Purchase Order exists)."
  def initial_state, do: :created

  @doc "The terminal state of the canonical Process — the journey is complete once it is reached."
  def final_state, do: List.last(ordered_states())

  @doc """
  The activity Bedrock watches for the receive-after-pay pattern: a goods receipt
  recorded once the journey has already reached the terminal (paid) state is a
  notable control signal, so it earns its own Conformance Deviation kind. This is
  the one landmark the conformance classifier cannot derive structurally — it
  lives here on the Process model, beside the transition that defines the activity,
  rather than buried in the classifier.
  """
  def goods_receipt_activity, do: :receive_goods

  @doc """
  Advance one step along the canonical Process.

  Returns `{:ok, next_state}` when `activity` is a legal transition out of
  `state`, otherwise `:error` (the activity diverges from the expected shape).
  """
  def advance(state, activity) do
    case Enum.find(transitions(), fn t -> t.action == activity and state in from(t) end) do
      nil -> :error
      transition -> {:ok, to(transition)}
    end
  end

  @doc "The canonical `{from_state, to_state}` for an activity, regardless of where a journey currently is."
  def edge(activity) do
    case Enum.find(transitions(), &(&1.action == activity)) do
      nil -> :error
      transition -> {:ok, hd(from(transition)), to(transition)}
    end
  end

  @doc "The canonical states in happy-path order, derived by walking transitions from the initial state."
  def ordered_states, do: ordered_states(initial_state(), [])

  @doc "The canonical activities in happy-path order, derived by walking transitions from the initial state."
  def activities, do: ordered_activities(initial_state(), [])

  @doc "The position of `state` along the canonical path; lower happens earlier."
  def rank(state), do: Enum.find_index(ordered_states(), &(&1 == state))

  defp ordered_states(state, acc) do
    case Enum.find(transitions(), &(state in from(&1))) do
      nil -> Enum.reverse([state | acc])
      transition -> ordered_states(to(transition), [state | acc])
    end
  end

  defp ordered_activities(state, acc) do
    case Enum.find(transitions(), &(state in from(&1))) do
      nil -> Enum.reverse(acc)
      transition -> ordered_activities(to(transition), [transition.action | acc])
    end
  end

  defp transitions, do: AshStateMachine.Info.state_machine_transitions(__MODULE__)

  defp from(transition), do: List.wrap(transition.from)
  defp to(transition), do: transition.to |> List.wrap() |> hd()
end
