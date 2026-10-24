defmodule KeepsakesWeb.PageControllerTest do
  use KeepsakesWeb.ConnCase, async: true

  import Keepsakes.AccountsFixtures

  test "GET / shows the interim home with sign-up and log-in links", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    refute Enum.empty?(LazyHTML.query(document, "#home-hero"))
    refute Enum.empty?(LazyHTML.query(document, ~s(#home-register[href="/users/register"])))
    refute Enum.empty?(LazyHTML.query(document, ~s(#home-log-in[href="/users/log-in"])))
  end

  test "GET / sends logged-in users to their albums", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/albums"
  end
end
