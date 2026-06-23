defmodule Bedrock.Compliance.HardEvidence do
  @moduledoc """
  The verdict-bearing, system-recorded facts behind a `Case` — in Slice 1, a
  snapshot of the offending Odoo record captured at detection time. Tenant-scoped;
  belongs to the `Case`.

  The append-only, hash-chained Evidence Ledger (ADR-0005, ADR-0009) is deferred
  to a later slice; here it is a plain frozen snapshot.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hard_evidence"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:snapshot]
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :snapshot, :map do
      allow_nil? false
      public? true
    end

    attribute :captured_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :case, Bedrock.Compliance.Case do
      allow_nil? false
    end
  end
end
