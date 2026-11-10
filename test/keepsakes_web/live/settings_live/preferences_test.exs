defmodule KeepsakesWeb.SettingsLive.PreferencesTest do
  @moduledoc "Notifications and Sharing defaults tabs, and where they take effect."
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Accounts, Sharing}
  alias Keepsakes.Accounts.Scope

  setup :register_and_log_in_user

  # The sign-up fixture's confirmation email
  setup do
    assert_email_sent(subject: "Confirm your Keepsake account")
    :ok
  end

  test "notification switches save as they change", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/notifications")

    lv
    |> form("#notifications-form",
      user: %{notify_guest_activity: "false", notify_product_news: "true"}
    )
    |> render_change()

    user = Accounts.get_user!(user.id)
    assert {user.notify_guest_activity, user.notify_product_news} == {false, true}
  end

  test "sharing defaults set up new links", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/app/settings/sharing")

    lv
    |> form("#sharing-form",
      user: %{share_expires_in: "7", share_default_view: "slideshow", share_show_details: "false"}
    )
    |> render_change()

    scope = Scope.for_user(Accounts.get_user!(user.id))
    album = album_fixture(scope)
    {:ok, link} = Sharing.create_link(scope, album, "auto")

    assert link.default_view == "slideshow"
    refute link.show_details
    assert Keepsakes.Billing.days_until(link.expires_at) == 7
  end

  describe "guest activity email" do
    setup %{scope: scope} do
      album = album_fixture(scope, name: "Our Little One")
      %{link: share_link_fixture(scope, album)}
    end

    test "sums visits since last time, then starts again", %{link: link} do
      :ok = Sharing.record_open(link)
      :ok = Sharing.record_open(link)

      assert Sharing.send_guest_digests() == 1
      assert_email_sent(subject: "Our Little One was opened twice in the last day")

      assert Sharing.send_guest_digests() == 0
    end

    test "isn't sent when turned off", %{link: link, user: user} do
      {:ok, _} = Accounts.update_notifications(user, %{notify_guest_activity: false})
      :ok = Sharing.record_open(link)

      assert Sharing.send_guest_digests() == 0
      refute_email_sent()
    end
  end
end
