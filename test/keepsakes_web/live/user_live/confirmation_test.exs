defmodule KeepsakesWeb.UserLive.ConfirmationTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  alias Keepsakes.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), confirmed_user: user_fixture()}
  end

  defp login_token(user) do
    extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)
  end

  describe "Confirm user" do
    test "renders the confirm form for an unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{login_token(user)}")
      assert has_element?(lv, "#confirmation_form")
    end

    test "renders the login form for a confirmed user", %{conn: conn, confirmed_user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{login_token(user)}")
      refute has_element?(lv, "#confirmation_form")
      assert has_element?(lv, ~s(#login_form button[name="user[remember_me]"]))
    end

    test "renders a single log in button for an already logged in user", %{
      conn: conn,
      confirmed_user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{login_token(user)}")
      assert has_element?(lv, "#login_form")
      refute has_element?(lv, ~s(#login_form button[name="user[remember_me]"]))
    end

    test "renders the reset form for reset links", %{conn: conn, confirmed_user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{login_token(user)}?reset=1")
      assert has_element?(lv, ~s(#reset_form[action="/users/log-in?_action=reset"]))
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_user: user} do
      token = login_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form = form(lv, "#confirmation_form", %{"user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Accounts.get_user!(user.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :user_token)

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "That link is invalid or it has expired"
    end

    test "logs confirmed user in without changing confirmed_at", %{
      conn: conn,
      confirmed_user: user
    } do
      token = login_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form = form(lv, "#login_form", %{"user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
      assert Accounts.get_user!(user.id).confirmed_at == user.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "That link is invalid or it has expired"
    end

    test "redirects for an invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "That link is invalid or it has expired"
    end
  end
end
