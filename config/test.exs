import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Credentials come from DB_* env vars (see config/runtime.exs and .env.example).
config :keepsakes, Keepsakes.Repo,
  database: "keepsakes_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :keepsakes, KeepsakesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dg5ZvS5Zbtt8kMBxOQhOplt4xkIcPdckODHoj8nGGEMXBL0bCH6kCIOTvHcZ9xBB",
  server: false

# Jobs are enqueued but only run when a test drains them explicitly
config :keepsakes, Oban, testing: :manual

# Local disk storage under tmp/ so tests never touch a real bucket
config :keepsakes, Keepsakes.Storage,
  adapter: Keepsakes.Storage.Local,
  root: Path.expand("../tmp/test_uploads", __DIR__)

# Read settings straight from the (sandboxed) DB in tests
config :keepsakes, Keepsakes.Settings.Cache, enabled: false

# Don't record test-raised exceptions
config :error_tracker, enabled: false

# In test we don't send emails
config :keepsakes, Keepsakes.Mailer, adapter: Swoosh.Adapters.Test

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
