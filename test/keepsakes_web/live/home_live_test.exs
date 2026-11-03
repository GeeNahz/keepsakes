defmodule KeepsakesWeb.HomeLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures

  alias Keepsakes.{Billing, Repo, Settings}
  alias Keepsakes.Billing.Price

  describe "landing page" do
    test "has every section and links to sign-up", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      for id <- ~w(hero how-it-works features use-cases templates pricing faq final-cta) do
        assert has_element?(lv, "##{id}"), "missing ##{id}"
      end

      assert has_element?(lv, ~s(#hero-start[href="/auth/register"]))
      assert has_element?(lv, ~s(#final-start[href="/auth/register"]))
      assert has_element?(lv, ~s(#nav-log-in[href="/auth/log-in"]))
      assert has_element?(lv, ~s(#site-footer a[href="/privacy"]))
    end

    test "signed-in visitors go to their albums", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:live_redirect, %{to: "/app/albums"}}} = live(conn, ~p"/")
    end

    test "the trial length and FAQ follow the settings", %{conn: conn} do
      {:ok, _} = Settings.put(:trial_days, 45)
      {:ok, _} = Settings.put(:grace_days, 5)

      {:ok, lv, _html} = live(conn, ~p"/")
      assert has_element?(lv, "#hero", "45-day free trial")
      assert has_element?(lv, "#faq-1", "45 days")
      assert has_element?(lv, "#faq-1", "5 more days")
    end
  end

  describe "pricing" do
    test "shows the public plans' live prices in NGN by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      plus = Billing.get_plan!("plus") |> Repo.preload(:prices)

      assert has_element?(lv, "#pricing-free-amount", "Free")

      assert has_element?(
               lv,
               "#pricing-plus-amount",
               Price.format(Billing.price(plus, "NGN", "month"))
             )

      assert has_element?(lv, "#plan-plus-collaborator_seats", "2 collaborators")
    end

    test "switches currency and interval, with the yearly saving", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      pro = Billing.get_plan!("pro") |> Repo.preload(:prices)

      lv |> element(~s(#pricing-currency button[phx-value-to="USD"])) |> render_click()

      assert has_element?(
               lv,
               "#pricing-pro-amount",
               Price.format(Billing.price(pro, "USD", "month"))
             )

      lv |> element(~s(#pricing-interval button[phx-value-to="year"])) |> render_click()

      assert has_element?(
               lv,
               "#pricing-pro-amount",
               Price.format(Billing.price(pro, "USD", "year"))
             )

      # $12 × 12 = $144 against $120 a year
      assert has_element?(lv, "#pricing-pro-saving", "Save $24")
      assert has_element?(lv, "#pricing-pro-saving", "17%")
    end

    test "hidden plans stay hidden", %{conn: conn} do
      Billing.get_plan!("pro") |> Ecto.Changeset.change(public: false) |> Repo.update!()
      {:ok, lv, _html} = live(conn, ~p"/")
      refute has_element?(lv, "#pricing-pro")
      assert has_element?(lv, "#pricing-plus")
    end
  end

  describe "search engines" do
    test "the home page has a description, OG tags and structured data", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      document = LazyHTML.from_document(html)

      assert [_] = LazyHTML.query(document, ~s(meta[name="description"])) |> Enum.to_list()
      assert [_] = LazyHTML.query(document, ~s(meta[property="og:image"])) |> Enum.to_list()
      assert [_] = LazyHTML.query(document, ~s(link[rel="canonical"])) |> Enum.to_list()

      [json] =
        Regex.run(~r{<script[^>]*type="application/ld\+json">(.*?)</script>}s, html,
          capture: :all_but_first
        )

      assert %{"@type" => "SoftwareApplication", "offers" => [_ | _]} = Jason.decode!(json)
    end

    test "robots.txt lets crawlers into public pages only", %{conn: conn} do
      body = main_host(conn) |> get("/robots.txt") |> response(200)
      assert body =~ "Allow: /"
      assert body =~ "Disallow: /app/"
      assert body =~ "Disallow: /a/"
      assert body =~ "Sitemap: http://localhost"
    end

    test "the admin host tells crawlers to stay out", %{conn: conn} do
      body =
        %{conn | host: KeepsakesWeb.Hosts.admin_host()} |> get("/robots.txt") |> response(200)

      assert body == "User-agent: *\nDisallow: /\n"
    end

    test "sitemap.xml lists the public pages", %{conn: conn} do
      conn = conn |> main_host() |> get("/sitemap.xml")
      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "application/xml"
      assert conn.resp_body =~ "<urlset"
      assert conn.resp_body =~ "<loc>#{KeepsakesWeb.Endpoint.url()}/privacy</loc>"
    end

    test "only the main site has a sitemap", %{conn: conn} do
      assert %{conn | host: KeepsakesWeb.Hosts.admin_host()}
             |> get("/sitemap.xml")
             |> response(404)
    end
  end

  defp main_host(conn), do: %{conn | host: KeepsakesWeb.Endpoint.host()}

  describe "legal pages" do
    test "terms and privacy render their sections", %{conn: conn} do
      terms = conn |> get(~p"/terms") |> html_response(200)
      for id <- ~w(terms-uploads terms-payments terms-ending), do: assert(terms =~ ~s(id="#{id}"))

      privacy = build_conn() |> get(~p"/privacy") |> html_response(200)

      for id <- ~w(privacy-what privacy-processors privacy-cookies privacy-rights),
          do: assert(privacy =~ ~s(id="#{id}"))

      assert privacy =~ "Data Protection Act 2023"
    end
  end
end
