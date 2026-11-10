defmodule KeepsakesWeb.SettingsLive.TemplatesTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.{Accounts, Templates}

  setup :register_and_log_in_user

  test "picking the template for new albums", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/templates")
    assert has_element?(lv, "#default-trail", "Used for new albums")

    lv |> element("#use-default-daylight") |> render_click()
    assert has_element?(lv, "#default-daylight", "Used for new albums")

    scope = Accounts.Scope.for_user(Accounts.get_user!(user.id))
    assert Templates.default_for(scope).slug == "daylight"
    assert album_fixture(scope).template_id == Templates.get_template(scope, "daylight").id
  end

  test "premium templates offer an upgrade on Free", %{conn: conn, user: user} do
    put_on_plan(user, "free")
    {:ok, lv, _html} = live(conn, ~p"/app/settings/templates")

    assert has_element?(lv, ~s(#upgrade-default-daylight[href="/app/settings/billing"]))
    refute has_element?(lv, "#use-default-daylight")
  end
end
