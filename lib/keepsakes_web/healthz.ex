defmodule KeepsakesWeb.Healthz do
  @moduledoc """
  `GET /healthz`: 200 `ok` when the app is up and can reach its database,
  503 otherwise. Docker's health check and the deploy script wait on it
  before sending traffic to a new container (`deploy/server/bin/deploy`),
  and UptimeRobot watches it from outside.

  Answered early in the endpoint, before logging, sessions, maintenance
  mode and routing, so it's cheap and works on any host. It reveals
  nothing beyond up or down.
  """
  @behaviour Plug

  import Plug.Conn

  # A stuck database should fail the check quickly, not hang it
  @db_timeout 1_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: ["healthz"]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    {status, body} = if database_up?(), do: {200, "ok"}, else: {503, "unavailable"}

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp database_up? do
    match?(
      {:ok, _},
      Ecto.Adapters.SQL.query(Keepsakes.Repo, "SELECT 1", [], timeout: @db_timeout)
    )
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
