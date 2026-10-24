defmodule KeepsakesWeb.MediaControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  alias Keepsakes.Storage

  setup do
    key = "tests/media-#{System.unique_integer([:positive])}.webp"
    :ok = Storage.put(key, "image-bytes")
    on_exit(fn -> Storage.delete(key) end)
    %{key: key}
  end

  test "serves a file for a valid token", %{conn: conn, key: key} do
    conn = get(conn, Storage.url(key))

    assert response(conn, 200) == "image-bytes"
    assert response_content_type(conn, :webp) =~ "image/webp"
    assert get_resp_header(conn, "cache-control") == ["private, max-age=3600, immutable"]
  end

  test "rejects tampered and expired tokens", %{conn: conn, key: key} do
    assert conn |> get(~p"/media/not-a-token") |> response(404)

    expired = Storage.url(key, expires_in: -7200, now: System.system_time(:second))
    assert conn |> get(expired) |> response(404)
  end

  test "404s when the object is gone", %{conn: conn, key: key} do
    url = Storage.url(key)
    :ok = Storage.delete(key)
    assert conn |> get(url) |> response(404)
  end

  test "signed URLs are identical within a 15-minute window", %{key: key} do
    base = 1_800_000_000 - rem(1_800_000_000, 900)

    assert Storage.url(key, now: base + 1) == Storage.url(key, now: base + 899)
    refute Storage.url(key, now: base + 1) == Storage.url(key, now: base + 901)
  end
end
