defmodule Bedrock.Accounts do
  use Ash.Domain,
    otp_app: :bedrock

  resources do
    resource Bedrock.Accounts.Token
    resource Bedrock.Accounts.User
  end
end
