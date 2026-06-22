defmodule Bedrock.Accounts.OauthClient do
  use Ash.Resource,
    otp_app: :bedrock,
    domain: Bedrock.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "oauth_clients"
    repo Bedrock.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [
        :client_name,
        :redirect_uris,
        :grant_types,
        :response_types,
        :token_endpoint_auth_method,
        :scope
      ]
    end

    update :touch do
      accept []
      change atomic_update(:last_used_at, expr(now()))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :client_name, :string do
      allow_nil? false
      public? true
    end

    attribute :redirect_uris, {:array, :string} do
      allow_nil? false
      public? true
    end

    attribute :grant_types, {:array, :string} do
      public? true
    end

    attribute :response_types, {:array, :string} do
      public? true
    end

    attribute :token_endpoint_auth_method, :string do
      public? true
    end

    attribute :scope, :string do
      public? true
    end

    attribute :last_used_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end
end
