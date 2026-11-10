defmodule KeepsakesWeb.SuspendedLoginTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.Customers

  setup do
    user = user_fixture() |> set_password()
    {:ok, user, _tokens} = Customers.suspend(staff_scope_fixture(), user, "Spam")
    %{user: user}
  end

  test "a suspended account can't log in with its password", %{conn: conn, user: user} do
    conn =
      post(conn, ~p"/auth/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/auth/log-in"
    refute get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "suspended"
  end

  test "or with an emailed link", %{conn: conn, user: user} do
    {token, _hashed} = generate_user_magic_link_token(user)
    conn = post(conn, ~p"/auth/log-in", %{"user" => %{"token" => token}})

    assert redirected_to(conn) == ~p"/auth/log-in"
    refute get_session(conn, :user_token)
  end
end
