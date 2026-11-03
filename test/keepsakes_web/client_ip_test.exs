defmodule KeepsakesWeb.ClientIPTest do
  use KeepsakesWeb.ConnCase, async: true

  alias KeepsakesWeb.ClientIP

  defp from(ip, headers) do
    Enum.reduce(headers, %{build_conn() | remote_ip: ip}, fn {k, v}, conn ->
      Plug.Conn.put_req_header(conn, k, v)
    end)
    |> ClientIP.call([])
  end

  describe "behind the edge proxy" do
    test "takes the visitor's address and scheme from the proxy's headers" do
      conn =
        from({172, 20, 0, 3}, [{"x-forwarded-for", "41.58.1.9"}, {"x-forwarded-proto", "https"}])

      assert conn.remote_ip == {41, 58, 1, 9}
      assert conn.scheme == :https
    end

    test "uses the last address, the one our proxy wrote" do
      conn = from({10, 0, 0, 2}, [{"x-forwarded-for", "6.6.6.6, 41.58.1.9"}])
      assert conn.remote_ip == {41, 58, 1, 9}
    end

    test "ignores nonsense" do
      conn = from({10, 0, 0, 2}, [{"x-forwarded-for", "not-an-ip"}])
      assert conn.remote_ip == {10, 0, 0, 2}
    end
  end

  test "headers from anyone else are not believed" do
    conn =
      from({41, 58, 1, 9}, [{"x-forwarded-for", "127.0.0.1"}, {"x-forwarded-proto", "https"}])

    assert conn.remote_ip == {41, 58, 1, 9}
    assert conn.scheme == :http
  end

  describe "IPv4 callers on an IPv6 socket (::ffff:a.b.c.d)" do
    test "a private one is the proxy" do
      # ::ffff:172.30.0.10, as the release sees OpenResty
      conn = from({0, 0, 0, 0, 0, 0xFFFF, 0xAC1E, 0x000A}, [{"x-forwarded-for", "41.58.1.9"}])
      assert conn.remote_ip == {41, 58, 1, 9}
    end

    test "a public one is not" do
      # ::ffff:41.58.1.9
      conn = from({0, 0, 0, 0, 0, 0xFFFF, 0x293A, 0x0109}, [{"x-forwarded-for", "127.0.0.1"}])
      assert conn.remote_ip == {0, 0, 0, 0, 0, 0xFFFF, 0x293A, 0x0109}
    end
  end

  test "the certificate check refuses outside visitors arriving through the proxy", %{conn: conn} do
    conn =
      %{conn | host: "app", remote_ip: {172, 20, 0, 3}}
      |> put_req_header("x-forwarded-for", "41.58.1.9")
      |> get("/internal/tls/ask?domain=#{KeepsakesWeb.Endpoint.host()}")

    assert conn.status == 403
  end

  test "rate limits count each visitor separately behind the proxy", %{conn: conn} do
    a =
      %{conn | remote_ip: {172, 20, 0, 3}}
      |> put_req_header("x-forwarded-for", "41.58.1.9")
      |> ClientIP.call([])

    b =
      %{conn | remote_ip: {172, 20, 0, 3}}
      |> put_req_header("x-forwarded-for", "102.89.4.4")
      |> ClientIP.call([])

    refute KeepsakesWeb.AuthThrottle.client_ip(a) == KeepsakesWeb.AuthThrottle.client_ip(b)
  end
end
