defmodule KeepsakesWeb.AlbumLive.ShareTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Sharing

  setup :register_and_log_in_user

  setup %{scope: scope} do
    album = album_fixture(scope, name: "Our Little One")
    %{album: album}
  end

  test "album page links to sharing and the preview once it has photos", %{
    conn: conn,
    scope: scope,
    album: album
  } do
    {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")
    assert has_element?(lv, "#share-album[disabled]")

    guest_memory_fixture(scope, album)
    {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")
    assert has_element?(lv, ~s(#share-album[href="/app/albums/#{album.slug}/share"]))
    assert has_element?(lv, ~s(#preview-as-guest[href="/a/preview/#{album.slug}/timeline"]))
  end

  describe "not shared yet" do
    test "shows the setup card and creates an automatic code", %{
      conn: conn,
      scope: scope,
      album: album
    } do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")
      assert has_element?(lv, "#share-setup")
      refute has_element?(lv, "#share-live")
      refute has_element?(lv, "#share-settings-form")

      lv |> form("#share-create-form", %{mode: "auto"}) |> render_submit()

      link = Sharing.get_link(scope, album)
      assert has_element?(lv, "#share-live")
      assert has_element?(lv, ~s(#share-link-url[value$="/a/#{link.slug}"]))
      assert has_element?(lv, ~s(#share-code[aria-label="Access code #{link.code}"]))
      assert has_element?(lv, "#share-live", "Generated automatically")
      assert has_element?(lv, "#invite-message", link.code)
      assert has_element?(lv, ~s(#open-as-guest[href="/a/#{link.slug}"]))
      assert has_element?(lv, "#share-activity", "Not opened yet")
    end

    test "your own code is validated", %{conn: conn, scope: scope, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")

      lv |> form("#share-create-form", %{mode: "manual"}) |> render_change()
      assert has_element?(lv, "#share-own-code")

      lv |> form("#share-create-form", %{mode: "manual", code: "123456"}) |> render_submit()
      assert has_element?(lv, "#share-code-hint", "too easy to guess")
      assert Sharing.get_link(scope, album) == nil

      lv |> form("#share-create-form", %{mode: "manual", code: "482917"}) |> render_submit()
      assert has_element?(lv, ~s(#share-code[aria-label="Access code 482917"]))
      assert has_element?(lv, "#share-live", "Set by you")
    end
  end

  describe "shared" do
    setup %{scope: scope, album: album} do
      %{link: share_link_fixture(scope, album)}
    end

    test "changing the code", %{conn: conn, scope: scope, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")

      lv |> element("#change-code") |> render_click()
      assert has_element?(lv, "#change-code-panel")

      lv |> form("#own-code-form", %{code: "12"}) |> render_submit()
      assert has_element?(lv, "#share-code-hint", "Enter exactly 6 numbers.")

      lv |> form("#own-code-form", %{code: "305172"}) |> render_submit()
      assert has_element?(lv, ~s(#share-code[aria-label="Access code 305172"]))
      refute has_element?(lv, "#change-code-panel")

      lv |> element("#change-code") |> render_click()
      lv |> element("#regenerate-code") |> render_click()
      link = Sharing.get_link(scope, album)
      assert link.code_version == 3
      assert link.code_origin == "auto"
      assert has_element?(lv, ~s(#share-code[aria-label="Access code #{link.code}"]))
    end

    test "settings save as they change", %{conn: conn, scope: scope, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")

      lv
      |> form("#share-settings-form",
        share_link: %{default_view: "slideshow", expires_in: "30", allow_downloads: "true"}
      )
      |> render_change()

      link = Sharing.get_link(scope, album)
      assert link.default_view == "slideshow"
      assert link.allow_downloads
      assert link.expires_at
      assert has_element?(lv, "#share_link_expires_in option[selected]", "Expires")
    end

    test "activity shows visits", %{conn: conn, album: album, link: link} do
      :ok = Sharing.record_open(link)
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")
      assert has_element?(lv, "#share-activity", "Opened once · last opened just now")
    end

    test "turning sharing off", %{conn: conn, scope: scope, album: album} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")

      lv |> element("#turn-off-sharing") |> render_click()
      assert has_element?(lv, "#share-setup")
      assert Sharing.get_link(scope, album) == nil
    end
  end

  test "another owner's album is not found", %{conn: conn} do
    other = album_fixture(user_scope_fixture())
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/app/albums/#{other.slug}/share") end
  end
end
