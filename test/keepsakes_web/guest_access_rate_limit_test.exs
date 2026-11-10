defmodule KeepsakesWeb.GuestAccessRateLimitTest do
  # Not async: switches the (globally disabled in test) rate limiter on
  use KeepsakesWeb.ConnCase, async: false

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  setup do
    previous = Application.get_env(:keepsakes, Keepsakes.RateLimit)
    Application.put_env(:keepsakes, Keepsakes.RateLimit, enabled: true)
    on_exit(fn -> Application.put_env(:keepsakes, Keepsakes.RateLimit, previous) end)

    scope = user_scope_fixture()
    album = album_fixture(scope)
    %{link: share_link_fixture(scope, album)}
  end

  test "five tries per link and IP, then even the right code waits", %{conn: conn, link: link} do
    conn = %{conn | remote_ip: {10, 9, 8, System.unique_integer([:positive]) |> rem(250)}}

    for _ <- 1..5 do
      result = post(conn, ~p"/a/#{link.slug}/access", %{"code" => "000001"})
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "didn't work"
    end

    result = post(conn, ~p"/a/#{link.slug}/access", %{"code" => "482917"})
    assert redirected_to(result) == "/a/#{link.slug}"
    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many tries"
  end
end
