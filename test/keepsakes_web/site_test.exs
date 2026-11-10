defmodule KeepsakesWeb.SiteTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.DomainsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Domains, Repo}
  alias Keepsakes.Accounts.Scope

  setup %{conn: conn} do
    owner = user_fixture(first_name: "Adaobi")
    scope = Scope.for_user(owner)
    domain = domain_fixture(owner)

    album = album_fixture(scope, %{name: "Lagos Trip"})
    guest_memory_fixture(scope, album, %{title: "Beach day"})
    link = share_link_fixture(scope, album)
    {:ok, _} = Domains.show_on_site(scope, album, true)

    %{
      conn: %{conn | host: domain.hostname},
      owner: owner,
      domain: domain,
      album: album,
      link: link
    }
  end

  describe "the public site" do
    test "lists the chosen albums", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#site", "Adaobi")
      assert has_element?(view, "#site-album-#{album.id}", "Lagos Trip")
    end

    test "opens an album with its access code", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, "/" <> album.slug)
      assert has_element?(view, ~s(#access-form[action="/#{album.slug}/access"]))

      bad = post(conn, "/#{album.slug}/access", %{"code" => "000000"})
      assert redirected_to(bad) == "/" <> album.slug

      conn = post(conn, "/#{album.slug}/access", %{"code" => "482917"})
      assert redirected_to(conn) == "/#{album.slug}/timeline"

      {:ok, view, _html} = conn |> recycle() |> live("/#{album.slug}/timeline")
      assert render(view) =~ "Beach day"
    end

    test "the timeline needs the code first", %{conn: conn, album: album} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, "/#{album.slug}/timeline")
      assert to == "/" <> album.slug
    end

    test "main-site pages don't exist here", %{conn: conn} do
      assert get(conn, "/app/albums").status == 404
      assert get(conn, "/auth/log-in").status == 404
    end

    test "albums of other accounts aren't reachable", %{conn: conn} do
      other = user_fixture()
      other_scope = Scope.for_user(other)
      theirs = album_fixture(other_scope, %{name: "Not yours"})
      share_link_fixture(other_scope, theirs)

      {:ok, view, _html} = live(conn, "/" <> theirs.slug)
      refute render(view) =~ "Not yours"
    end
  end

  describe "hosts" do
    test "a blocked or unverified domain shows nothing", %{conn: conn, domain: domain} do
      domain |> Ecto.Changeset.change(status: "blocked") |> Repo.update!()
      assert get(conn, "/").status == 404
    end

    test "unknown hosts get the main app", %{conn: conn} do
      conn = %{conn | host: "something-else.example"}
      assert get(conn, "/").status == 200
    end
  end

  describe "certificate check" do
    test "allows our hosts and verified domains, nobody else", %{conn: conn, domain: domain} do
      conn = %{conn | host: "app"}
      assert get(conn, "/internal/tls/ask?domain=#{domain.hostname}").status == 200

      assert get(conn, "/internal/tls/ask?domain=#{KeepsakesWeb.Hosts.admin_host()}").status ==
               200

      assert get(conn, "/internal/tls/ask?domain=random.example.org").status == 404

      domain |> Ecto.Changeset.change(status: "pending") |> Repo.update!()
      assert get(conn, "/internal/tls/ask?domain=#{domain.hostname}").status == 404
    end

    test "only answers the private network", %{conn: conn, domain: domain} do
      conn = %{conn | host: "app", remote_ip: {8, 8, 8, 8}}
      assert get(conn, "/internal/tls/ask?domain=#{domain.hostname}").status == 403
    end
  end

  test "a suspended owner's site stops", %{conn: conn, owner: owner} do
    {:ok, _, _} = Keepsakes.Customers.suspend(staff_scope_fixture(), owner, "Spam")
    assert get(conn, "/").status == 404
  end
end
