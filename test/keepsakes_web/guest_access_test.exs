defmodule KeepsakesWeb.GuestAccessTest do
  use KeepsakesWeb.ConnCase, async: true
  use Oban.Testing, repo: Keepsakes.Repo

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Repo, Sharing}
  alias KeepsakesWeb.GuestAccess

  setup do
    owner = user_fixture(%{first_name: "Godswill"})
    scope = Keepsakes.Accounts.Scope.for_user(owner)
    album = album_fixture(scope, name: "Our Little One")
    guest_memory_fixture(scope, album, %{title: "First birthday"})
    %{owner: owner, scope: scope, album: album, link: share_link_fixture(scope, album)}
  end

  defp enter(conn, link, code), do: post(conn, ~p"/a/#{link.slug}/access", %{"code" => code})

  describe "access page" do
    test "asks for the code", %{conn: conn, link: link} do
      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}")

      assert has_element?(lv, "#access-album-name", "Our Little One")
      assert render(lv) =~ "Godswill shared an album with you"
      assert has_element?(lv, ~s(#access-form[action="/a/#{link.slug}/access"]))
      assert has_element?(lv, "#access-digits input[name='code[]']")
    end

    test "unknown links are not available", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/a/nothing-here")
      assert has_element?(lv, "#link-unavailable", "isn't available")
    end

    test "expired links say so", %{conn: conn, scope: scope, link: link} do
      {:ok, _} = Sharing.update_settings(scope, link, %{"expires_in" => "7"})

      link
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -60))
      |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}")
      assert has_element?(lv, "#link-unavailable", "expired")
      assert redirected_to(enter(conn, link, "482917")) == "/a/#{link.slug}"
    end

    test "is skipped for guests who already unlocked it", %{conn: conn, link: link} do
      conn = conn |> enter(link, "482917") |> recycle()
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}")
      assert to == "/a/#{link.slug}/timeline"
    end

    test "the owner never needs the code", %{conn: conn, owner: owner, link: link} do
      conn = log_in_user(conn, owner)
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}")
      assert to == "/a/#{link.slug}/timeline"
      assert Repo.reload!(link).open_count == 0
    end
  end

  describe "entering the code" do
    test "a wrong code goes back with a message", %{conn: conn, link: link} do
      conn = enter(conn, link, "111111")
      assert redirected_to(conn) == "/a/#{link.slug}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't work"
    end

    test "the right code opens the timeline and counts a visit", %{conn: conn, link: link} do
      conn = enter(conn, link, ~w(4 8 2 9 1 7))

      assert redirected_to(conn) == "/a/#{link.slug}/timeline"
      assert get_session(conn, "guest_links") == %{link.id => 1}
      assert Repo.reload!(link).open_count == 1

      {:ok, lv, _html} = conn |> recycle() |> live(~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, "#timeline")
    end

    test "opens the owner's chosen view", %{conn: conn, scope: scope, link: link} do
      {:ok, link} = Sharing.update_settings(scope, link, %{"default_view" => "slideshow"})
      assert redirected_to(enter(conn, link, "482917")) == "/a/#{link.slug}/slideshow"

      {:ok, link} = Sharing.update_settings(scope, link, %{"default_view" => "autoscroll"})

      assert redirected_to(enter(build_conn(), link, "482917")) ==
               "/a/#{link.slug}/timeline?auto=1"
    end

    test "changing the code locks out old guests", %{conn: conn, scope: scope, link: link} do
      conn = conn |> enter(link, "482917") |> recycle()
      {:ok, _} = Sharing.change_code(scope, link, "manual", "305172")

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}/timeline")
      assert to == "/a/#{link.slug}"
    end

    test "turning sharing off locks everyone out", %{conn: conn, scope: scope, link: link} do
      conn = conn |> enter(link, "482917") |> recycle()
      {:ok, _} = Sharing.delete_link(scope, link)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/a/#{link.slug}/timeline")
      assert to == "/a/#{link.slug}"
    end

    test "the session remembers a limited number of links", %{conn: conn, link: link} do
      stale = for i <- 1..25, into: %{}, do: {"old-#{i}", 1}
      conn = conn |> init_test_session(%{"guest_links" => stale}) |> GuestAccess.grant(link)

      links = get_session(conn, "guest_links")
      assert map_size(links) == 20
      assert links[link.id] == 1
    end
  end

  describe "downloads" do
    setup %{scope: scope, album: album} do
      memory = draft_fixture(scope, album)

      {:ok, memory} =
        Keepsakes.Albums.update_memory(scope, memory, %{title: "Beach day", month: 12, year: 2019})

      {:ok, _} = Keepsakes.Albums.publish_drafts(scope, album)
      :ok = perform_job(Keepsakes.Media.ProcessMemory, %{memory_id: memory.id})
      %{memory: memory}
    end

    test "only when the owner allows them", %{
      conn: conn,
      scope: scope,
      link: link,
      memory: memory
    } do
      path = ~p"/a/#{link.slug}/photos/#{memory.id}/download"
      guest = conn |> enter(link, "482917") |> recycle()

      assert guest |> get(path) |> response(404)

      {:ok, _} = Sharing.update_settings(scope, link, %{"allow_downloads" => "true"})
      conn = get(guest, path)
      assert response(conn, 200) =~ "WEBP"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "beach-day.webp"
    end

    test "never without access", %{conn: conn, scope: scope, link: link, memory: memory} do
      {:ok, _} = Sharing.update_settings(scope, link, %{"allow_downloads" => "true"})
      assert conn |> get(~p"/a/#{link.slug}/photos/#{memory.id}/download") |> response(404)
    end
  end
end
