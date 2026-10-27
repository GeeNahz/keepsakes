defmodule KeepsakesWeb.DomainsLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.DomainsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Domains, Repo}
  alias Keepsakes.Accounts.Scope

  describe "owner settings" do
    setup :register_and_log_in_user

    test "coming soon until the flag is on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      assert has_element?(view, "#domains-soon")
    end

    test "an upgrade prompt without a plan that includes domains", %{conn: conn, user: user} do
      allow_domains(user)
      put_on_plan(user, "plus")
      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      assert has_element?(view, "#domains-upgrade")
    end

    test "adds a domain, shows its records, checks and removes it", %{conn: conn, user: user} do
      allow_domains(user)
      put_on_plan(user, "pro")
      host = unique_hostname()

      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      view |> form("#add-domain-form", domain: %{hostname: host}) |> render_submit()

      [domain] = Domains.list(Scope.for_user(user))
      assert has_element?(view, "#domain-#{domain.id}", "_keepsake." <> host)
      assert has_element?(view, "#domain-#{domain.id}", "edge.keepsake.test")
      refute has_element?(view, "#add-domain")

      publish_dns(domain)
      view |> element("#check-#{domain.id}") |> render_click()
      assert has_element?(view, "#domain-#{domain.id}", "Connected")

      view |> element("#remove-#{domain.id}") |> render_click()
      view |> element("#confirm-remove-#{domain.id}") |> render_click()
      assert Domains.list(Scope.for_user(user)) == []
    end

    test "an existing domain stays manageable if the flag goes off", %{conn: conn, user: user} do
      domain = domain_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      refute has_element?(view, "#domains-soon")
      assert has_element?(view, "#domain-#{domain.id}")
      assert has_element?(view, "#remove-#{domain.id}")
      refute has_element?(view, "#add-domain")
    end

    test "explains a refused name", %{conn: conn, user: user} do
      allow_domains(user)
      put_on_plan(user, "pro")
      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      view |> form("#add-domain-form", domain: %{hostname: "nope"}) |> render_submit()
      assert has_element?(view, "#add-domain-error")
    end

    test "chooses which shared albums appear on the site", %{conn: conn, user: user, scope: scope} do
      allow_domains(user)
      put_on_plan(user, "pro")
      shared = album_fixture(scope, %{name: "Shared"})
      share_link_fixture(scope, shared)
      private = album_fixture(scope, %{name: "Private"})

      {:ok, view, _html} = live(conn, ~p"/app/settings/domains")
      assert has_element?(view, "#show-album-#{private.id}[disabled]")

      view |> element("#show-album-#{shared.id}") |> render_click()
      assert Repo.reload!(shared).show_on_site
    end
  end

  describe "admin domains page" do
    test "lists, blocks and blocks names", %{conn: conn} do
      owner = user_fixture()
      domain = domain_fixture(owner)
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/domains")
      assert has_element?(view, "#domains-#{domain.id}", domain.hostname)

      view |> element("#block-domain-#{domain.id}") |> render_click()
      view |> form("#block-form", %{reason: "Phishing"}) |> render_submit()
      assert Repo.reload!(domain).status == "blocked"
      assert has_element?(view, "#unblock-domain-#{domain.id}")

      view
      |> form("#blocked-form", blocked_hostname: %{pattern: "*.scam.example", reason: "Scam"})
      |> render_submit()

      assert render(view) =~ "*.scam.example"
    end

    test "needs domains.manage", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["support"]))
      assert_error_sent 403, fn -> get(conn, ~p"/domains") end
    end
  end
end
