defmodule KeepsakesWeb.ClientIP do
  @moduledoc """
  The visitor's real address when requests come through our edge proxy
  (OpenResty, compose.yaml). Behind the proxy every connection comes from
  the proxy itself, so rate limits, the audit log and the private-network
  check of `/internal/tls/ask` would all see one address.

  The edge sets `X-Forwarded-For` to the address it saw (overwriting
  whatever the visitor sent) and `X-Forwarded-Proto` to `http`/`https`.
  Those headers are only believed when the connection itself comes from a
  private-network address, i.e. from the proxy; anyone on the internet who
  sends them directly is ignored. In production the app's port is only
  reachable from the proxy.

  As a plug (in the endpoint) it rewrites `conn.remote_ip` and
  `conn.scheme`; `from_socket/1` does the same for LiveView, whose
  connection comes with the proxy's headers in `:x_headers`.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if private?(conn.remote_ip) do
      conn
      |> put_ip(Plug.Conn.get_req_header(conn, "x-forwarded-for"))
      |> put_scheme(Plug.Conn.get_req_header(conn, "x-forwarded-proto"))
    else
      conn
    end
  end

  defp put_ip(conn, values) do
    case forwarded_ip(values) do
      nil -> conn
      ip -> %{conn | remote_ip: ip}
    end
  end

  defp put_scheme(conn, ["https" | _]), do: %{conn | scheme: :https}
  defp put_scheme(conn, _values), do: conn

  @doc """
  A LiveView's client address (an `:inet` tuple), from `:peer_data` and,
  when the peer is our proxy, `:x_headers`. Nil before the socket connects.
  """
  def from_socket(socket) do
    peer = Phoenix.LiveView.get_connect_info(socket, :peer_data)
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

    case peer do
      %{address: address} ->
        forwarded =
          if private?(address),
            do:
              headers
              |> Enum.filter(&(elem(&1, 0) == "x-forwarded-for"))
              |> Enum.map(&elem(&1, 1))
              |> forwarded_ip()

        forwarded || address

      _ ->
        nil
    end
  end

  # The last entry is the one our proxy wrote (it overwrites the header, so
  # normally it's the only one); earlier entries could have come from anyone
  defp forwarded_ip(values) do
    with [_ | _] <- values,
         last when is_binary(last) <-
           values
           |> Enum.join(",")
           |> String.split(",")
           |> Enum.map(&String.trim/1)
           |> List.last(),
         {:ok, ip} <- :inet.parse_address(String.to_charlist(last)) do
      ip
    else
      _ -> nil
    end
  end

  @doc "Whether an address is loopback or private-network (where our proxy lives)."
  def private?({127, _, _, _}), do: true
  def private?({10, _, _, _}), do: true
  def private?({172, b, _, _}) when b in 16..31, do: true
  def private?({192, 168, _, _}), do: true
  def private?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def private?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: true

  # An IPv4 caller on an IPv6 socket (the release listens on `::`) arrives
  # as ::ffff:a.b.c.d; judge the IPv4 address inside it
  def private?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: private?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  def private?(_ip), do: false
end
