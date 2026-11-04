defmodule KeepsakesWeb.MetricsEndpoint do
  @moduledoc """
  The metrics listener's only page: `GET /metrics` in Prometheus's text
  format (`Keepsakes.PromEx`). Runs on its own port, separate from the
  site, so the edge proxy never exposes it. Everything else is a 404.
  """
  @behaviour Plug

  import Plug.Conn

  @prom_ex PromEx.Plug.init(prom_ex_module: Keepsakes.PromEx, path: "/metrics")

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = PromEx.Plug.call(conn, @prom_ex)
    if conn.halted or conn.state != :unset, do: conn, else: send_resp(conn, 404, "")
  end
end
