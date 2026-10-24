defmodule KeepsakesWeb.UserSessionControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures
  alias Keepsakes.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  defp assert_logged_in_shell(conn) do
    response = conn |> get(~p"/albums") |> html_response(200)
    document = LazyHTML.from_document(response)
    refute Enum.empty?(LazyHTML.query(document, "#user-menu"))
    refute Enum.empty?(LazyHTML.query(document, "#user-menu-log-out"))
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/albums"
      assert_logged_in_shell(conn)
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_keepsakes_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/albums"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "welcomes a freshly registered user", %{conn: conn, unconfirmed_user: user} do
      conn =
        post(conn, ~p"/users/log-in?_action=registered", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/albums"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome to Keepsake"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/albums"
      assert_logged_in_shell(conn)
    end

    test "confirms the registrant from their own session and keeps the password", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/log-in?_action=confirmed", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/albums"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your email is confirmed."

      confirmed = Accounts.get_user!(user.id)
      assert confirmed.confirmed_at
      assert confirmed.hashed_password
    end

    test "confirms from another browser, removes the password and asks for a new one", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in?_action=confirmed", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/settings#password"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Set a password"

      confirmed = Accounts.get_user!(user.id)
      assert confirmed.confirmed_at
      refute confirmed.hashed_password
    end

    test "password reset links land on the password section", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in?_action=reset", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/settings#password"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Choose a new password"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/confirm/resend" do
    test "re-sends the confirmation email to an unconfirmed user", %{
      conn: conn,
      unconfirmed_user: user
    } do
      conn = conn |> log_in_user(user) |> post(~p"/users/confirm/resend")

      assert redirected_to(conn) == ~p"/albums"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Sent!"
      assert Keepsakes.Repo.get_by(Accounts.UserToken, user_id: user.id, context: "login")
    end

    test "does nothing for a confirmed user", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/users/confirm/resend")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already confirmed"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
