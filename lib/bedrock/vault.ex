defmodule Bedrock.Vault do
  @moduledoc """
  Cloak vault used by `ash_cloak` to encrypt sensitive fields at rest — notably
  the read-only Odoo `Connection` credential (ADR-0007). Ciphers are configured
  per environment; in production the key is supplied via the environment.
  """
  use Cloak.Vault, otp_app: :bedrock
end
