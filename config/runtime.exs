import Config
import Dotenvy

# Load env vars from a gitignored `.env` (and `.env.<env>`) at the project
# root when present. Real environment variables always win. Releases have
# no .env files, so only the container's environment applies there.
# Every variable read below is documented in `.env.example`.
project_root = Path.expand("..", __DIR__)

source!([
  Path.join(project_root, ".env"),
  Path.join(project_root, ".env.#{config_env()}"),
  System.get_env()
])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/keepsakes start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :keepsakes, KeepsakesWeb.Endpoint, server: true
end

config :keepsakes, KeepsakesWeb.Endpoint, http: [port: env!("PORT", :integer, 4000)]

# Local Postgres for dev/test (prod uses DATABASE_URL below)
if config_env() in [:dev, :test] do
  config :keepsakes, Keepsakes.Repo,
    username: env!("DB_USER", :string, "postgres"),
    password: env!("DB_PASS", :string, "postgres"),
    hostname: env!("DB_HOST", :string, "localhost"),
    port: env!("DB_PORT", :integer, 5432)
end

# Encryption at rest for sensitive columns (access codes, TOTP secrets,
# gateway tokens). The fallback key is for dev/test only.
cloak_key =
  if config_env() == :prod do
    env!("CLOAK_KEY", :string)
  else
    env!("CLOAK_KEY", :string?, nil) || "slicKIYnX3WbZIL9SNNqZj8ULVZOxtSDCumAStf8nek="
  end

config :keepsakes, Keepsakes.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12}
  ]

# Place names from photo GPS (OpenStreetMap Nominatim). Tests set :none.
if config_env() != :test do
  geocoder =
    case env!("GEOCODER", :string?, nil) do
      "none" -> :none
      _ -> :nominatim
    end

  config :keepsakes, Keepsakes.Media.Geocoder, adapter: geocoder
end

# Photo storage: S3-compatible (Cloudflare R2 / DigitalOcean Spaces) when
# S3_BUCKET is set, otherwise local disk. Tests configure their own in test.exs.
if config_env() != :test do
  case env!("S3_BUCKET", :string?, nil) do
    nil ->
      default_dir =
        if config_env() == :prod,
          do: "/var/lib/keepsakes/uploads",
          else: Path.join(project_root, "priv/uploads")

      config :keepsakes, Keepsakes.Storage,
        adapter: Keepsakes.Storage.Local,
        root: env!("LOCAL_UPLOADS_DIR", :string?, nil) || default_dir,
        x_accel_prefix: env!("LOCAL_X_ACCEL_PREFIX", :string?, nil)

    bucket ->
      config :keepsakes, Keepsakes.Storage,
        adapter: Keepsakes.Storage.S3,
        bucket: bucket,
        endpoint_url: env!("S3_ENDPOINT", :string),
        region: env!("S3_REGION", :string?, nil) || "auto",
        access_key_id: env!("S3_ACCESS_KEY_ID", :string),
        secret_access_key: env!("S3_SECRET_ACCESS_KEY", :string)
  end
end

# Payments: Flutterwave v3 (test-mode keys in dev/staging, live keys in
# production). Tests stub the API with Req.Test (config/test.exs).
if config_env() != :test do
  config :keepsakes, Keepsakes.Billing.Gateways.Flutterwave,
    public_key: env!("FLW_PUBLIC_KEY", :string?, nil),
    secret_key: env!("FLW_SECRET_KEY", :string?, nil),
    encryption_key: env!("FLW_ENCRYPTION_KEY", :string?, nil),
    secret_hash: env!("FLW_SECRET_HASH", :string?, nil)
end

# Email: Resend in prod; in dev only when MAIL_DELIVERY=resend (otherwise
# mail lands in the local /dev/mailbox). Tests always use Swoosh.Adapters.Test.
config :keepsakes, :mail_from, {
  env!("MAIL_FROM_NAME", :string?, nil) || "Keepsake",
  env!("MAIL_FROM_ADDRESS", :string?, nil) || "hello@example.com"
}

# New support tickets and customer replies are emailed here (until the
# admin portal's inbox exists). Empty: no emails.
if config_env() != :test do
  config :keepsakes, :support_inbox, env!("SUPPORT_INBOX", :string?, nil)

  # Granted Super Admin at startup and when this address signs up; takes
  # precedence over (but doesn't replace) `mix keepsakes.staff.grant`
  config :keepsakes, :super_admin_email, env!("SUPER_ADMIN_EMAIL", :string?, nil)

  # Staff without two-step login must set it up before getting in.
  # Off for now; set to true for production (see docs/learning/admin-subdomain.md).
  config :keepsakes,
         :require_staff_two_step,
         env!("REQUIRE_STAFF_TWO_STEP", :boolean?, nil) || false

  # Must start with "admin." like in prod (the router matches that prefix)
  dev_admin_host = config_env() == :dev && env!("ADMIN_HOST", :string?, nil)

  if dev_admin_host && String.starts_with?(dev_admin_host, "admin."),
    do: config(:keepsakes, :admin_host, dev_admin_host)
end

mail_delivery =
  env!("MAIL_DELIVERY", :string?, nil) || if(config_env() == :prod, do: "resend", else: "local")

if config_env() != :test and mail_delivery == "resend" do
  config :keepsakes, Keepsakes.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: env!("RESEND_API_KEY", :string)

  config :swoosh, api_client: Swoosh.ApiClient.Req, local: false
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :keepsakes, Keepsakes.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :keepsakes, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # The staff portal answers only on its own host: admin.<PHX_HOST> unless
  # ADMIN_HOST says otherwise. See docs/learning/admin-subdomain.md.
  admin_host = System.get_env("ADMIN_HOST") || "admin." <> host

  # The router picks admin routes by the "admin." prefix (compiled in)
  String.starts_with?(admin_host, "admin.") ||
    raise "ADMIN_HOST must start with \"admin.\" (got #{inspect(admin_host)})"

  config :keepsakes, :admin_host, admin_host

  config :keepsakes, KeepsakesWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    # LiveView sockets may come from the main site or the admin portal
    check_origin: ["//#{host}", "//#{admin_host}"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :keepsakes, KeepsakesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :keepsakes, KeepsakesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
