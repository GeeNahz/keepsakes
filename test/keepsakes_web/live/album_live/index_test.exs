defmodule KeepsakesWeb.AlbumLive.IndexTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  test "requires a logged-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/auth/log-in"}}} = live(conn, ~p"/app/albums")
  end

  describe "owner shell" do
    setup :register_and_log_in_user

    test "renders the empty state, sidebar, storage meter and avatar menu", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/app/albums")

      assert has_element?(lv, "#albums-empty")
      assert has_element?(lv, "#album-sidebar")
      assert has_element?(lv, "#storage-meter")

      assert has_element?(
               lv,
               ~s(#user-menu-button [aria-label="#{Keepsakes.Accounts.User.full_name(user)}"])
             )

      assert has_element?(lv, ~s(#user-menu-settings[href="/app/settings/profile"]))
      refute has_element?(lv, "#confirm-email-banner")
    end

    test "creates the first album from the empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums")

      assert lv
             |> form("#first-album-form", album: %{name: ""})
             |> render_change() =~ "Give your album a name"

      {:ok, show, _html} =
        lv
        |> form("#first-album-form", album: %{name: "Our Little One"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/app/albums/our-little-one")

      assert has_element?(show, "#album-title", "Our Little One")
      assert has_element?(show, "#sidebar-albums a[aria-current=page]", "Our Little One")
    end

    test "opens the newest album when there are albums", %{conn: conn, scope: scope} do
      older = Keepsakes.AlbumsFixtures.album_fixture(scope, name: "Older")
      Keepsakes.AlbumsFixtures.album_fixture(scope, name: "Newer")

      older
      |> Ecto.Changeset.change(inserted_at: DateTime.add(older.inserted_at, -3600))
      |> Keepsakes.Repo.update!()

      assert {:error, {:live_redirect, %{to: "/app/albums/newer"}}} = live(conn, ~p"/app/albums")
    end

    test "unconfirmed users see the confirm-email banner", %{conn: conn} do
      conn = log_in_user(conn, unconfirmed_user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/app/albums")

      assert has_element?(lv, "#confirm-email-banner")
      assert has_element?(lv, ~s(#resend-confirmation-form[action="/app/confirm-email/resend"]))
    end
  end
end
