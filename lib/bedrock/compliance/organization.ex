defmodule Bedrock.Compliance.Organization do
  @moduledoc """
  A customer tenant — the company whose Odoo instance is audited. Lives in the
  public schema and provisions its own per-tenant Postgres schema (`org_<id>`)
  via `manage_tenant` (ADR-0007). Owns one or more `Connection`s.
  """
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "organizations"
    repo Bedrock.Repo

    manage_tenant do
      template ["org_", :id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  defimpl Ash.ToTenant do
    def to_tenant(%{id: id}, _resource), do: "org_#{id}"
  end
end
