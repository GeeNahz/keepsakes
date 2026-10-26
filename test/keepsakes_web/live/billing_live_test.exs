defmodule KeepsakesWeb.BillingLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  setup :register_and_log_in_user

  describe "/app/billing" do
    test "shows the trial, usage and the three plans", %{conn: conn, scope: scope} do
      album_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/app/billing")

      assert has_element?(lv, "#current-plan-name", "Free trial")
      assert has_element?(lv, "#current-plan-status", "60 days left")
      assert has_element?(lv, "#plan-free-max_albums", "2 albums")
      assert has_element?(lv, "#usage-albums", "1 · unlimited")
      assert has_element?(lv, "#plan-free")
      assert has_element?(lv, "#plan-plus", "₦5,000")
      assert has_element?(lv, "#plan-pro-max_albums", "Unlimited")
      assert has_element?(lv, "#plan-free-premium_templates .hero-minus")
      assert has_element?(lv, "#choose-plus", "Choose Plus")
      refute has_element?(lv, "#choose-plus[disabled]")
    end

    test "switches currency and interval", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/billing")

      lv |> element(~s(#currency-switch button[phx-value-to="USD"])) |> render_click()
      lv |> element(~s(#interval-switch button[phx-value-to="year"])) |> render_click()

      assert has_element?(lv, "#plan-plus", "$50")
      assert has_element?(lv, "#plan-pro", "$120")
    end

    test "marks Free as current and shows the over-limit banner", %{
      conn: conn,
      scope: scope,
      user: user
    } do
      for _ <- 1..3, do: album_fixture(scope)
      put_on_plan(user, "free")

      {:ok, lv, _html} = live(conn, ~p"/app/billing")
      assert has_element?(lv, "#plan-free", "Current")
      assert has_element?(lv, "#choose-free[disabled]")
      assert has_element?(lv, "#usage-albums", "3 of 2")
      assert has_element?(lv, "#over-limit-banner", "album limit (3 of 2)")
    end
  end

  describe "limits in the owner portal" do
    test "the sidebar shows the plan's storage and status", %{
      conn: conn,
      scope: scope,
      user: user
    } do
      album = album_fixture(scope)
      put_on_plan(user, "free")

      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")
      assert has_element?(lv, "#storage-meter", "of 1 GB")
      assert has_element?(lv, ~s(#sidebar-plan[href="/app/billing"]), "Free plan")
    end

    test "the New album dialog explains a full plan", %{conn: conn, scope: scope, user: user} do
      album = album_fixture(scope)
      album_fixture(scope)
      put_on_plan(user, "free")

      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")
      assert has_element?(lv, "#album-limit-notice", "Your plan includes 2 albums")
      refute has_element?(lv, "#new-album-form")
    end

    test "an upload over the limit explains why", %{conn: conn, scope: scope, user: user} do
      album = album_fixture(scope)
      put_on_plan(user, plan_fixture(%{"max_memories_per_album" => 0}))

      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}")

      photo =
        file_input(lv, "#upload-form", :photos, [
          %{name: "IMG_1.jpg", content: jpeg(), type: "image/jpeg"}
        ])

      render_upload(photo, "IMG_1.jpg")

      assert has_element?(lv, "#limit-notice", "IMG_1.jpg wasn't added")
      assert has_element?(lv, ~s(#limit-notice-plans[href="/app/billing"]))
      assert Keepsakes.Albums.list_drafts(scope, album) == []
    end

    test "guest downloads need the plan", %{conn: conn, scope: scope, user: user} do
      album = album_fixture(scope)
      share_link_fixture(scope, album)
      put_on_plan(user, "free")

      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/share")
      assert has_element?(lv, "#share_link_allow_downloads[disabled]")
      assert has_element?(lv, ~s(#downloads-upgrade[href="/app/billing"]))
    end

    test "premium templates offer an upgrade", %{conn: conn, scope: scope, user: user} do
      album = album_fixture(scope)
      put_on_plan(user, "free")

      {:ok, lv, _html} = live(conn, ~p"/app/albums/#{album.slug}/template")
      assert has_element?(lv, "#template-daylight", "Premium")
      assert has_element?(lv, ~s(#upgrade-daylight[href="/app/billing"]))
      refute has_element?(lv, "#use-daylight")
      assert render_click(lv, "use", %{"slug" => "daylight"}) =~ "need the Plus or Pro plan"
    end
  end
end
