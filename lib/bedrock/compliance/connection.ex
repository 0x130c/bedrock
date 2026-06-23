defmodule Bedrock.Compliance.Connection do
  @moduledoc """
  A configured link to one Odoo instance: its URL, a dedicated read-only Odoo
  credential (encrypted at rest with `ash_cloak`, ADR-0007), and sync state.
  Tenant-scoped to its `Organization`'s schema.

  Also hosts the `ingest_events` seam: it accepts a batch of normalized Odoo
  records and runs the deterministic detection pipeline.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshCloak]

  postgres do
    table "connections"
    repo Bedrock.Repo
  end

  cloak do
    vault(Bedrock.Vault)
    attributes [:credential]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :odoo_url, :credential]
    end

    action :ingest_events, {:array, :struct} do
      description "Run the deterministic detection pipeline over a batch of normalized Odoo records."

      argument :connection, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      argument :records, {:array, :map}, allow_nil?: false

      run Bedrock.Compliance.Ingestion
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :odoo_url, :string do
      allow_nil? false
      public? true
    end

    attribute :credential, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :last_synced_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end
end
