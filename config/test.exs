import Config
config :bedrock, token_signing_secret: "ccwHwt+2X47acfbiXNqyEzpTSROmZXKO"

config :bedrock, Bedrock.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("ct8Cyj0o1gjjN8HtTk10k4GKq8oDY54FWlxJ5Cdzj70=")}
  ]

config :bcrypt_elixir, log_rounds: 1
config :bedrock, Oban, testing: :manual

# The Context Weaver (Layer 3) uses a deterministic fake LLM in tests — no real
# calls. Per-test behavior is steered via `:context_weaver_stub`.
config :bedrock, :context_weaver_llm, Bedrock.Test.ContextWeaverStub
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bedrock, Bedrock.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bedrock_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bedrock, BedrockWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QvZvUcamVWFPFaw8lpV3mbx8MbFEPFZSiryJTkodMfMRKF+FSh0bcJEnG5gtZtp0",
  server: false

# In test we don't send emails
config :bedrock, Bedrock.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
