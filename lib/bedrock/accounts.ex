defmodule Bedrock.Accounts do
  use Ash.Domain,
    otp_app: :bedrock

  resources do
    resource Bedrock.Accounts.Token
    resource Bedrock.Accounts.User
    resource Bedrock.Accounts.OauthClient
    resource Bedrock.Accounts.OauthAuthorizationCode
    resource Bedrock.Accounts.OauthRefreshToken
    resource Bedrock.Accounts.OauthConsent
  end
end
