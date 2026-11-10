defmodule KeepsakesWeb.OwnerShellTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AlbumsFixtures

  setup :register_and_log_in_user

  test "every portal page has the header and album sidebar", %{conn: conn, scope: scope} do
    album = album_fixture(scope)

    for path <- [
          ~p"/app/albums/#{album.slug}",
          ~p"/app/albums/#{album.slug}/upload",
          ~p"/app/albums/#{album.slug}/share",
          ~p"/app/albums/#{album.slug}/template",
          ~p"/app/settings/profile",
          ~p"/app/settings/account",
          ~p"/app/settings/security",
          ~p"/app/settings/notifications",
          ~p"/app/settings/sharing",
          ~p"/app/settings/templates",
          ~p"/app/settings/billing",
          ~p"/app/settings/referrals",
          ~p"/app/settings/domains",
          ~p"/app/settings/privacy"
        ] do
      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "#user-menu"), "no header on #{path}"

      assert has_element?(lv, "#album-sidebar #sidebar-album-#{album.id}"),
             "no sidebar on #{path}"

      assert has_element?(lv, "#album-sidebar #storage-meter"), "no storage meter on #{path}"
    end
  end
end
