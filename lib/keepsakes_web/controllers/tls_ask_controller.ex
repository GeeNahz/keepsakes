defmodule KeepsakesWeb.TlsAskController do
  @moduledoc """
  `GET /internal/tls/ask?domain=<host>`: OpenResty asks this before it
  requests a certificate for a hostname (on-demand TLS, Stage 8b). It
  answers 200 for our own hosts and customers' verified, non-blocked
  domains, and 404 for anything else, so nobody can make us issue
  certificates for names that aren't ours or our customers'.

  Only callers on loopback or a private network (the Docker network) are
  answered, and, when `TLS_ASK_TOKEN` is set, only with that token in the
  `x-tls-ask-token` header.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Domains

  plug :internal_only

  def show(conn, %{"domain" => domain}) do
    host = Domains.normalize(domain)

    allowed? =
      host in [KeepsakesWeb.Endpoint.host(), KeepsakesWeb.Hosts.admin_host()] or
        Domains.site_for_host(host) != nil

    send_resp(conn, if(allowed?, do: 200, else: 404), "")
  end

  def show(conn, _params), do: send_resp(conn, 400, "")

  defp internal_only(conn, _opts) do
    token = Application.get_env(:keepsakes, :tls_ask_token)

    token_ok? =
      token in [nil, ""] or
        Plug.Crypto.secure_compare(
          List.first(get_req_header(conn, "x-tls-ask-token")) || "",
          token
        )

    # remote_ip is already the visitor's real address (KeepsakesWeb.ClientIP),
    # so someone on the internet reaching this through the proxy is refused
    if KeepsakesWeb.ClientIP.private?(conn.remote_ip) and token_ok?,
      do: conn,
      else: conn |> send_resp(403, "") |> halt()
  end
end
