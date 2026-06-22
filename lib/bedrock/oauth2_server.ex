defmodule Bedrock.Oauth2Server do
  @moduledoc """
  OAuth 2.1 authorization-server configuration.

  See `AshAuthentication.Oauth2Server` for all options.
  """

  use AshAuthentication.Oauth2Server,
    otp_app: :bedrock,
    user_resource: Bedrock.Accounts.User,
    issuer_url: {Bedrock.Secrets, []},
    resource_url: {Bedrock.Secrets, []},
    signing_secret: {Bedrock.Secrets, []},
    client_resource: Bedrock.Accounts.OauthClient,
    authorization_code_resource: Bedrock.Accounts.OauthAuthorizationCode,
    refresh_token_resource: Bedrock.Accounts.OauthRefreshToken,
    consent_resource: Bedrock.Accounts.OauthConsent,
    scopes: ["mcp"],
    # Dynamic client registration (RFC 7591). The library default is
    # `false` for safety; the installer turns it on because most
    # people setting up an OAuth server today need it for MCP-style
    # flows (ChatGPT Apps SDK, Claude.ai connectors, etc.). Set to
    # `false` if your auth server is for a fixed set of first-party
    # clients only.
    dcr_enabled?: true,
    sign_in_path: "/sign-in"
end
