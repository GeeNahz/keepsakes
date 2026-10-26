defmodule KeepsakesWeb.LoginStepControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures

  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.TwoStep

  setup do
    user = user_fixture() |> set_password()
    %{user: user}
  end

  defp log_in(conn, user) do
    post(conn, ~p"/auth/log-in", %{
      "user" => %{"email" => user.email, "password" => valid_user_password()}
    })
  end

  describe "two-step login" do
    setup %{user: user} do
      secret = TwoStep.new_secret()
      {:ok, user, codes} = TwoStep.enable(user, secret, NimbleTOTP.verification_code(secret))
      %{user: user, secret: secret, codes: codes}
    end

    test "asks for a code before logging in", %{conn: conn, user: user, secret: secret} do
      conn = log_in(conn, user)
      assert redirected_to(conn) == ~p"/auth/two-step"
      refute get_session(conn, :user_token)

      conn = conn |> recycle() |> get(~p"/auth/two-step")
      assert html_response(conn, 200) =~ "Two-step login"

      bad = conn |> recycle() |> post(~p"/auth/two-step", %{"code" => "000000"})
      assert html_response(bad, 200) =~ "That code didn&#39;t work"
      refute get_session(bad, :user_token)

      good =
        conn
        |> recycle()
        |> post(~p"/auth/two-step", %{"code" => NimbleTOTP.verification_code(secret)})

      assert redirected_to(good) == ~p"/app/albums"
      assert get_session(good, :user_token)
    end

    test "a recovery code also works", %{conn: conn, user: user, codes: [code | _]} do
      conn = log_in(conn, user) |> recycle() |> post(~p"/auth/two-step", %{"code" => code})
      assert get_session(conn, :user_token)
    end

    test "the page needs a password first", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/auth/two-step")) == ~p"/auth/log-in"
    end
  end

  describe "a paused account" do
    test "can be restored at login", %{conn: conn, user: user} do
      {:ok, _user, _tokens} = Accounts.request_deletion(user)

      conn = log_in(conn, user)
      assert redirected_to(conn) == ~p"/auth/restore"

      conn = conn |> recycle() |> get(~p"/auth/restore")
      assert html_response(conn, 200) =~ "Restore your account?"

      conn = conn |> recycle() |> post(~p"/auth/restore")
      assert redirected_to(conn) == ~p"/app/albums"
      assert get_session(conn, :user_token)
      refute Accounts.get_user!(user.id).deletion_requested_at
    end

    test "Not now leaves it paused", %{conn: conn, user: user} do
      {:ok, _user, _tokens} = Accounts.request_deletion(user)

      conn = log_in(conn, user) |> recycle() |> delete(~p"/auth/two-step/cancel")
      assert redirected_to(conn) == ~p"/auth/log-in"
      assert Accounts.get_user!(user.id).deletion_requested_at
    end
  end
end
