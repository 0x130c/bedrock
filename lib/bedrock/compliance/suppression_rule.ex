defmodule Bedrock.Compliance.SuppressionRule do
  @moduledoc """
  A known-good pattern marked as expected (ADR-0010): a vendor whose payments
  legitimately cluster at month-end, an out-of-band approval, and the like. While a
  matching rule is in force, findings on its `{control_name, subject}` still open a
  `Case` (recall is preserved) but never promote to an `Alert`.

  Fed by `dismissed` Case reasons (an Auditor dismissing a Case as known-good) or
  authored directly. Tenant-scoped; unique on the pattern it suppresses.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "suppression_rules"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_pattern
      accept [:control_name, :subject, :reason]
    end

    read :matching do
      description "Suppression Rules matching a finding's Control and subject."
      argument :control_name, :string, allow_nil?: false
      argument :subject, :string, allow_nil?: false

      filter expr(control_name == ^arg(:control_name) and subject == ^arg(:subject))
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    # The Control whose findings this rule suppresses (its `control_name`).
    attribute :control_name, :string do
      allow_nil? false
      public? true
    end

    # The finding subject this rule scopes to — the same label a Control puts on its
    # finding (e.g. "Vendor V1", "PO 42").
    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    # Why this pattern is known-good — carried over from the dismissal reason when
    # fed by a dismissed Case.
    attribute :reason, :string do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_pattern, [:control_name, :subject]
  end
end
