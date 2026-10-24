defmodule KeepsakesWeb.GuestLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Sharing

  setup do
    owner = user_fixture(%{first_name: "Godswill"})
    scope = Keepsakes.Accounts.Scope.for_user(owner)
    album = album_fixture(scope, name: "Our Little One")
    %{owner: owner, scope: scope, album: album}
  end

  defp as_guest(conn, link),
    do: init_test_session(conn, %{"guest_links" => %{link.id => link.code_version}})

  describe "timeline" do
    setup %{scope: scope, album: album} do
      first =
        guest_memory_fixture(scope, album, %{
          title: "First birthday",
          month: 4,
          year: 2019,
          caption: "Fun and games",
          place: "Ikeja, Lagos"
        })

      {:ok, first} = Keepsakes.Albums.set_people(scope, first, ["Mum", "Dad"])
      second = guest_memory_fixture(scope, album, %{title: "Beach day", month: 12, year: 2019})

      third =
        guest_memory_fixture(scope, album, %{title: "First day of school", month: 9, year: 2021})

      _incomplete = memory_fixture(scope, album, %{title: "No date"})

      %{link: share_link_fixture(scope, album), memories: [first, second, third]}
    end

    test "needs the code", %{conn: conn, link: link} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}/timeline")
      assert to == "/a/#{link.slug}"
    end

    test "shows complete memories along the trail with year markers", %{
      conn: conn,
      link: link,
      memories: [first, second, third]
    } do
      {:ok, lv, html} = conn |> as_guest(link) |> live(~p"/a/#{link.slug}/timeline")

      assert has_element?(lv, "#timeline-summary", "3 MEMORIES · APR 2019 – SEP 2021")
      assert html =~ "An album by Godswill"
      assert html =~ ~r/First birthday.*Beach day.*First day of school/s
      refute html =~ "No date"

      assert has_element?(lv, "#entries-#{first.id}", "2019")
      refute has_element?(lv, "#entries-#{second.id} span.rounded-full", "2019")
      assert has_element?(lv, "#entries-#{third.id}", "2021")
      assert has_element?(lv, "#entries-#{first.id}", "Ikeja, Lagos · with Mum & Dad")
      assert has_element?(lv, "#entries-#{first.id}", "Fun and games")
      assert has_element?(lv, "#timeline-end", "To be continued")
      assert has_element?(lv, ~s(#play-slideshow[href="/a/#{link.slug}/slideshow"]))
      assert has_element?(lv, ~s(#autoscroll-bar[data-start="false"]))
      refute has_element?(lv, "#owner-preview-banner")
      refute has_element?(lv, "a[href$='/download']")
    end

    test "hides captions and places when the owner turns details off", %{
      conn: conn,
      scope: scope,
      link: link,
      memories: [first | _]
    } do
      {:ok, link} = Sharing.update_settings(scope, link, %{"show_details" => "false"})
      {:ok, lv, _html} = conn |> as_guest(link) |> live(~p"/a/#{link.slug}/timeline")

      refute has_element?(lv, "#entries-#{first.id}", "Fun and games")
      refute has_element?(lv, "#entries-#{first.id}", "with Mum")
    end

    test "offers downloads when allowed", %{
      conn: conn,
      scope: scope,
      link: link,
      memories: [first | _]
    } do
      {:ok, link} = Sharing.update_settings(scope, link, %{"allow_downloads" => "true"})
      {:ok, lv, _html} = conn |> as_guest(link) |> live(~p"/a/#{link.slug}/timeline")

      assert has_element?(lv, ~s(a[href="/a/#{link.slug}/photos/#{first.id}/download"]))
    end

    test "?auto=1 starts auto-scroll", %{conn: conn, link: link} do
      {:ok, lv, _html} = conn |> as_guest(link) |> live(~p"/a/#{link.slug}/timeline?auto=1")
      assert has_element?(lv, ~s(#autoscroll-bar[data-start="true"]))
    end

    test "the owner sees a preview banner", %{conn: conn, owner: owner, link: link} do
      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, "#owner-preview-banner", "own album")
    end
  end

  describe "slideshow" do
    setup %{scope: scope, album: album} do
      guest_memory_fixture(scope, album, %{title: "First birthday", month: 4, year: 2019})
      guest_memory_fixture(scope, album, %{title: "Beach day", month: 12, year: 2019})
      %{link: share_link_fixture(scope, album)}
    end

    test "renders every slide and stop", %{conn: conn, link: link} do
      {:ok, lv, _html} = conn |> as_guest(link) |> live(~p"/a/#{link.slug}/slideshow")

      assert has_element?(lv, "#slideshow-counter", "Memory 1 of 2")
      assert has_element?(lv, ~s(#slide-0[data-date="April 2019"]))
      assert has_element?(lv, ~s(#slide-1[aria-hidden="true"]))
      assert has_element?(lv, ~s(#slideshow [data-stop="1"]), "Dec '19")
      assert has_element?(lv, ~s(#exit-slideshow[href="/a/#{link.slug}/timeline"]))
    end

    test "needs the code", %{conn: conn, link: link} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/a/#{link.slug}/slideshow")
    end
  end

  describe "owner preview" do
    test "works before the album is shared", %{
      conn: conn,
      owner: owner,
      scope: scope,
      album: album
    } do
      guest_memory_fixture(scope, album, %{title: "First birthday"})
      conn = log_in_user(conn, owner)

      {:ok, lv, _html} = live(conn, ~p"/a/preview/#{album.slug}/timeline")
      assert has_element?(lv, "#owner-preview-banner", "Preview")
      assert has_element?(lv, ~s(#play-slideshow[href="/a/preview/#{album.slug}/slideshow"]))

      {:ok, slides, _html} = live(conn, ~p"/a/preview/#{album.slug}/slideshow")
      assert has_element?(slides, "#slideshow-counter", "Memory 1 of 1")
    end

    test "needs the owner", %{conn: conn, album: album} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/a/preview/#{album.slug}/timeline")

      stranger = conn |> log_in_user(user_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        live(stranger, ~p"/a/preview/#{album.slug}/timeline")
      end
    end

    test "empty albums show a gentle message", %{conn: conn, owner: owner, album: album} do
      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/a/preview/#{album.slug}/timeline")
      assert has_element?(lv, "#timeline-empty")
    end
  end
end
