defmodule KeepsakesWeb.PageControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures

  test "GET / shows the interim home with sign-up and log-in links", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    refute Enum.empty?(LazyHTML.query(document, "#home-hero"))
    refute Enum.empty?(LazyHTML.query(document, ~s(#home-register[href="/auth/register"])))
    refute Enum.empty?(LazyHTML.query(document, ~s(#home-log-in[href="/auth/log-in"])))
  end

  test "GET / sends logged-in users to their albums", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/app/albums"
  end

  test "GET /app opens the album list, and needs a login", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/app")) == ~p"/auth/log-in"

    conn = conn |> log_in_user(user_fixture()) |> get(~p"/app")
    assert redirected_to(conn) == ~p"/app/albums"
  end

  test "the portal and sign-in pages only live under /app and /auth", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    for path <- ["/albums", "/billing", "/users/settings", "/users/log-in", "/users/register"] do
      assert conn |> get(path) |> response(404)
    end
  end
end
