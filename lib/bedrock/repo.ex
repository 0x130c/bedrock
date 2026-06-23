defmodule Bedrock.Repo do
  use AshPostgres.Repo,
    otp_app: :bedrock

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    ["ash-functions", "citext", AshMoney.AshPostgresExtension]
  end

  # Returns every tenant schema, so `mix ash_postgres.migrate --tenants` can run
  # tenant migrations against each Organization's per-tenant schema (ADR-0007).
  @impl true
  def all_tenants do
    import Ecto.Query, only: [from: 2]

    all(from(o in "organizations", select: fragment("? || ?", "org_", type(o.id, :string))))
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
