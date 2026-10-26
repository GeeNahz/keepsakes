# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :keepsakes, :scopes,
  user: [
    default: true,
    module: Keepsakes.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Keepsakes.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :keepsakes,
  ecto_repos: [Keepsakes.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Every table and foreign key defaults to UUIDs, matching `--binary-id`,
# including hand-written migrations from `mix ecto.gen.migration`.
config :keepsakes, Keepsakes.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

# Background jobs (Postgres-backed, no Redis)
config :keepsakes, Oban,
  engine: Oban.Engines.Basic,
  repo: Keepsakes.Repo,
  queues: [default: 10, media: 4, mailers: 10, billing: 5, domains: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"7 * * * *", Keepsakes.Billing.LifecycleWorker},
       {"15 6 * * *", Keepsakes.HousekeepingWorker}
     ]}
  ]

# Feature flags, persisted in Postgres, cache-busted across nodes over PubSub
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Keepsakes.Repo,
  ecto_primary_key_type: :binary_id

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Keepsakes.PubSub

# Self-hosted error tracking stored in our own database
config :error_tracker,
  repo: Keepsakes.Repo,
  otp_app: :keepsakes,
  enabled: true

# The staff portal's host (prod derives it from PHX_HOST in runtime.exs).
# *.localhost resolves to this machine, so dev needs no hosts-file edits.
config :keepsakes, :admin_host, "admin.localhost"

# Whether staff must have two-step login to open the admin portal
# (REQUIRE_STAFF_TWO_STEP). Off for now; turn on for production.
config :keepsakes, :require_staff_two_step, false

# Configure the endpoint
config :keepsakes, KeepsakesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KeepsakesWeb.ErrorHTML, json: KeepsakesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Keepsakes.PubSub,
  live_view: [signing_salt: "pbMgiM89"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :keepsakes, Keepsakes.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  keepsakes: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  keepsakes: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
