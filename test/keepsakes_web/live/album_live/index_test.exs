defmodule KeepsakesWeb.AlbumLive.IndexTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  test "requires a logged-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/albums")
  end

  describe "owner shell" do
    setup :register_and_log_in_user

    test "renders the empty state, sidebar, storage meter and avatar menu", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/albums")

      assert has_element?(lv, "#albums-empty")
      assert has_element?(lv, "#album-sidebar")
      assert has_element?(lv, "#storage-meter")

      assert has_element?(
               lv,
               ~s(#user-menu-button [aria-label="#{Keepsakes.Accounts.User.full_name(user)}"])
             )

      assert has_element?(lv, ~s(#user-menu-settings[href="/users/settings"]))
      refute has_element?(lv, "#confirm-email-banner")
    end

    test "unconfirmed users see the confirm-email banner", %{conn: conn} do
      conn = log_in_user(conn, unconfirmed_user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/albums")

      assert has_element?(lv, "#confirm-email-banner")
      assert has_element?(lv, ~s(#resend-confirmation-form[action="/users/confirm/resend"]))
    end
  end
end
