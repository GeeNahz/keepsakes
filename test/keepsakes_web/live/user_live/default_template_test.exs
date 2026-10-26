defmodule KeepsakesWeb.UserLive.DefaultTemplateTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Accounts, Templates}

  setup :register_and_log_in_user

  test "picking the template for new albums", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings")
    assert has_element?(lv, ~s(#default_template_slug option[value="trail"][selected]))

    lv
    |> form("#default_template_form", default_template: %{slug: "daylight"})
    |> render_change()

    assert has_element?(lv, ~s(#default_template_slug option[value="daylight"][selected]))

    scope = Accounts.Scope.for_user(Accounts.get_user!(user.id))
    assert Templates.default_for(scope).slug == "daylight"
    assert album_fixture(scope).template_id == Templates.get_template(scope, "daylight").id
  end
end
