defmodule Keepsakes.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KeepsakesWeb.Telemetry,
      Keepsakes.Repo,
      {DNSCluster, query: Application.get_env(:keepsakes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Keepsakes.PubSub},
      Keepsakes.Vault,
      Keepsakes.Settings.Cache,
      {Keepsakes.RateLimit, clean_period: :timer.minutes(10)},
      {Oban, Application.fetch_env!(:keepsakes, Oban)},
      # Grants SUPER_ADMIN_EMAIL Super Admin once the database is up (one-off)
      Supervisor.child_spec({Task, &Keepsakes.Staff.ensure_configured_super_admin/0},
        id: :super_admin_bootstrap
      ),
      # Start to serve requests, typically the last entry
      KeepsakesWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Keepsakes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KeepsakesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
