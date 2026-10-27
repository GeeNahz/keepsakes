defmodule KeepsakesWeb.HostRouter do
  @moduledoc """
  Picks the router for a request by its host. A customer's verified
  domain (`Keepsakes.Domains.site_for_host/1`) goes to
  `KeepsakesWeb.SiteRouter`, their public site, with the domain in
  `conn.assigns.site`; everything else (the main site, the admin portal,
  internal calls) goes to `KeepsakesWeb.Router`.

  Phoenix routers can only match a fixed host prefix, and a customer's
  `/` has to be their site rather than our landing page, hence a second
  router. LiveView remembers which router rendered a page, so live
  navigation works on both. See docs/learning/admin-subdomain.md.
  """
  @behaviour Plug

  alias Keepsakes.Domains
  alias KeepsakesWeb.Hosts

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      Hosts.admin?(conn) or conn.host == KeepsakesWeb.Endpoint.host() ->
        main(conn)

      site = Domains.site_for_host(conn.host) ->
        conn
        |> Plug.Conn.assign(:site, site)
        |> KeepsakesWeb.SiteRouter.call(KeepsakesWeb.SiteRouter.init([]))

      # A customer's domain that isn't (or is no longer) connected: nothing here
      Domains.known_host?(conn.host) ->
        conn |> Plug.Conn.send_resp(404, "Not found") |> Plug.Conn.halt()

      # Anything else (internal calls by IP or container name) is the main app
      true ->
        main(conn)
    end
  end

  defp main(conn), do: KeepsakesWeb.Router.call(conn, KeepsakesWeb.Router.init([]))
end
