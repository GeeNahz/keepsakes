defmodule Keepsakes.PromEx do
  @moduledoc """
  Prometheus metrics: the BEAM, Phoenix, LiveView, Ecto and Oban.

  Started only when `METRICS_ENABLED=true` (`config :keepsakes, :metrics`),
  and then served by `KeepsakesWeb.MetricsEndpoint` on its own port (4021),
  which only the Docker network can reach: the edge never proxies it. The
  optional `metrics` profile on the server (Prometheus + Grafana) scrapes
  it; see DEPLOYMENT.md. Grafana's dashboards are PromEx's own, exported
  into `deploy/monitoring/grafana/dashboards/`.
  """
  use PromEx, otp_app: :keepsakes

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: KeepsakesWeb.Router, endpoint: KeepsakesWeb.Endpoint},
      Plugins.PhoenixLiveView,
      {Plugins.Ecto, repos: [Keepsakes.Repo]},
      {Plugins.Oban, oban_supervisors: [Oban]}
    ]
  end

  @impl true
  def dashboard_assigns do
    [datasource_id: "prometheus", default_selected_interval: "30s"]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "phoenix_live_view.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end

  @doc "PromEx plus its metrics listener, or nothing when metrics are off."
  def children do
    metrics = Application.get_env(:keepsakes, :metrics, [])

    if metrics[:enabled] do
      [
        __MODULE__,
        {Bandit,
         plug: KeepsakesWeb.MetricsEndpoint,
         port: Keyword.fetch!(metrics, :port),
         startup_log: false}
      ]
    else
      []
    end
  end
end
