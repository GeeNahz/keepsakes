defmodule KeepsakesWeb.Hosts do
  @moduledoc """
  One app, two hostnames: the main site (owner portal, sign-in, guest
  pages) and the staff portal on `admin.<host>` (`:admin_host` config).

  The router matches the admin routes by host, and these plugs make sure
  each side only answers on its own host: the main pipelines 404 on the
  admin host and the admin pipeline 404s anywhere else. Because cookies
  are host-only (no `Domain` attribute), the browser keeps a separate
  session for each host, so a customer login never carries over to the
  admin portal. See docs/learning/admin-subdomain.md.
  """
  import Plug.Conn

  @doc "The admin portal's host, e.g. `admin.keepsake.com` (`admin.localhost` in dev)."
  def admin_host, do: Application.fetch_env!(:keepsakes, :admin_host)

  @doc "Whether the request is for the admin portal."
  def admin?(%Plug.Conn{host: host}), do: host == admin_host()

  @doc "Plug: 404 on the admin host (main site routes)."
  def only_main_host(conn, _opts), do: if(admin?(conn), do: not_found(conn), else: conn)

  @doc "Plug: 404 anywhere but the admin host (admin routes)."
  def only_admin_host(conn, _opts), do: if(admin?(conn), do: conn, else: not_found(conn))

  @doc "Full URL of `path` on the admin portal, for emails and links from the main site."
  def admin_url(path) do
    uri = URI.parse(KeepsakesWeb.Endpoint.url())
    URI.to_string(%{uri | host: admin_host(), path: path})
  end

  defp not_found(conn) do
    conn
    |> put_status(404)
    |> Phoenix.Controller.put_format("html")
    |> Phoenix.Controller.put_view(html: KeepsakesWeb.ErrorHTML)
    |> Phoenix.Controller.render("404.html")
    |> halt()
  end
end
