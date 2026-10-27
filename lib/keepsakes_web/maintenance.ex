defmodule KeepsakesWeb.Maintenance do
  @moduledoc """
  Maintenance mode (`Settings.maintenance_mode`), as a plug in the
  endpoint before the router.

  While it's on, every main-site request gets the 503 maintenance page
  (`Settings.maintenance_message`, `Retry-After`), except payment webhooks,
  media links and dev tools. The admin portal is never affected.

  Staff can still look at the site: the admin portal links them to
  `/maintenance/bypass?token=…` (`bypass_url/1`), a token signed for them
  that lasts 12 hours. It sets a signed, host-only cookie on the main site,
  and pages then show a "only staff can see this" banner
  (`@maintenance_bypass`).
  """
  @behaviour Plug

  import Plug.Conn

  alias Keepsakes.{Accounts, Settings, Staff}
  alias KeepsakesWeb.Hosts

  @cookie "_keepsakes_maintenance_bypass"
  @salt "maintenance bypass"
  @max_age 12 * 60 * 60
  @always_open ["webhooks", "media", "dev"]

  @doc "A link that lets this staff member see the main site during maintenance."
  def bypass_url(%Accounts.User{id: id}) do
    token = Phoenix.Token.sign(KeepsakesWeb.Endpoint, @salt, id)
    KeepsakesWeb.Endpoint.url() <> "/maintenance/bypass?token=" <> URI.encode_www_form(token)
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      Hosts.admin?(conn) -> conn
      conn.path_info == ["maintenance", "bypass"] -> bypass(conn)
      not Settings.get(:maintenance_mode) -> conn
      List.first(conn.path_info) in @always_open -> conn
      staff_bypass?(conn) -> assign(conn, :maintenance_bypass, true)
      true -> closed(conn)
    end
  end

  defp bypass(conn) do
    conn = fetch_query_params(conn)

    case verify(conn.query_params["token"]) do
      {:ok, _user} ->
        conn
        |> put_resp_cookie(@cookie, conn.query_params["token"],
          sign: true,
          max_age: @max_age,
          http_only: true,
          same_site: "Lax"
        )
        |> Phoenix.Controller.redirect(to: "/")
        |> halt()

      :error ->
        closed(conn)
    end
  end

  defp staff_bypass?(conn) do
    conn = fetch_cookies(conn, signed: [@cookie])
    match?({:ok, _}, verify(conn.cookies[@cookie]))
  end

  # Still signed, still fresh, and still staff
  defp verify(token) when is_binary(token) do
    with {:ok, id} <- Phoenix.Token.verify(KeepsakesWeb.Endpoint, @salt, token, max_age: @max_age),
         %Accounts.User{} = user <- Accounts.get_user(id),
         true <- Staff.staff?(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp verify(_token), do: :error

  defp closed(conn) do
    html =
      Phoenix.Template.render_to_string(KeepsakesWeb.MaintenanceHTML, "page", "html",
        message: Settings.get(:maintenance_message)
      )

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("retry-after", "600")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(503, html)
    |> halt()
  end
end
