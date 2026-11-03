defmodule KeepsakesWeb.SeoController do
  @moduledoc """
  `/robots.txt` and `/sitemap.xml`, built from the endpoint's URL so
  production lists `https://<PHX_HOST>/...`.

  The main site lets crawlers in, except where pages are private (the
  portal, guest albums, sign-in, invitations, media). Any other host (the
  admin portal, and customers' domains, whose albums are behind codes)
  tells them to stay out.
  """
  use KeepsakesWeb, :controller

  @public_paths ["/", "/terms", "/privacy", "/auth/register"]
  @private_paths ~w(/app/ /a/ /auth/ /internal/ /invites/ /media/ /dev/)

  def robots(conn, _params) do
    body =
      if main_host?(conn) do
        Enum.join(
          ["User-agent: *", "Allow: /"] ++
            Enum.map(@private_paths, &"Disallow: #{&1}") ++
            ["", "Sitemap: #{url(~p"/sitemap.xml")}", ""],
          "\n"
        )
      else
        "User-agent: *\nDisallow: /\n"
      end

    conn |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    if main_host?(conn) do
      urls =
        for path <- @public_paths do
          "  <url><loc>#{KeepsakesWeb.Endpoint.url()}#{path}</loc></url>"
        end

      body =
        Enum.join(
          [
            ~s(<?xml version="1.0" encoding="UTF-8"?>),
            ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
            | urls
          ] ++ ["</urlset>", ""],
          "\n"
        )

      conn |> put_resp_content_type("application/xml") |> send_resp(200, body)
    else
      send_resp(conn, 404, "")
    end
  end

  defp main_host?(conn), do: conn.host == KeepsakesWeb.Endpoint.host()

  @doc false
  def public_paths, do: @public_paths
end
