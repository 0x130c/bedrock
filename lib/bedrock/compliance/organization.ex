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
      accept [:name, :materiality_floor]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    # The money-at-risk threshold below which a finding never promotes to an Alert
    # (it still opens a Case). One input to the promotion gate (ADR-0010). Defaults
    # to a small floor so material findings promote out of the box.
    attribute :materiality_floor, :money do
      allow_nil? false
      default fn -> Money.new(:VND, 10_000_000) end
      public? true
    end

    timestamps()
  end

  defimpl Ash.ToTenant do
    def to_tenant(%{id: id}, _resource), do: "org_#{id}"
  end
end
