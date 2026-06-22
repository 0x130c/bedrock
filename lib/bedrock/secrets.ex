defmodule Bedrock.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Bedrock.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:bedrock, :token_signing_secret)
  end

  def secret_for([:issuer_url], Bedrock.Oauth2Server, _opts, _context) do
    Application.fetch_env(:bedrock, :oauth2_issuer_url)
  end

  def secret_for([:resource_url], Bedrock.Oauth2Server, _opts, _context) do
    Application.fetch_env(:bedrock, :oauth2_resource_url)
  end

  def secret_for([:signing_secret], Bedrock.Oauth2Server, _opts, _context) do
    Application.fetch_env(:bedrock, :oauth2_signing_secret)
  end
end
