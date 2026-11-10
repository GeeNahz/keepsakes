defmodule KeepsakesWeb.AdminCustomersLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.Billing

  describe "customer list" do
    setup %{conn: conn} do
      %{conn: log_in_staff(conn, staff_fixture(["support"]))}
    end

    test "lists, searches and filters customers", %{conn: conn} do
      ada = user_fixture(first_name: "Ada")
      bola = user_fixture(first_name: "Bola")
      put_on_plan(bola, "free")

      {:ok, view, _html} = live(conn, ~p"/customers")
      assert has_element?(view, "#customers-#{ada.id}")
      assert has_element?(view, "#customers-#{bola.id}")

      view |> form("#customer-filters", customers: %{q: "ada"}) |> render_change()
      assert_patch(view, ~p"/customers?q=ada")
      assert has_element?(view, "#customers-#{ada.id}")
      refute has_element?(view, "#customers-#{bola.id}")

      {:ok, view, _html} = live(conn, ~p"/customers?plan=free")
      refute has_element?(view, "#customers-#{ada.id}")
      assert has_element?(view, "#customers-#{bola.id}")
    end

    test "loads 50 at a time", %{conn: conn} do
      for _ <- 1..51, do: user_fixture()

      {:ok, view, _html} = live(conn, ~p"/customers")
      assert view |> element("#customers") |> render() |> count_rows() == 50

      view |> element("#load-more-customers") |> render_click()
      assert view |> element("#customers") |> render() |> count_rows() == 51
      refute has_element?(view, "#load-more-customers")
    end

    test "is in the sidebar and linked from the dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#admin-nav-customers")
      assert has_element?(view, ~s(#stat-trials[href="/customers?status=trialing"]))
    end

    test "needs users.view", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["finance"]))
      assert_error_sent 403, fn -> get(conn, ~p"/customers") end
    end
  end

  # Rows only parse inside a table; the empty-state row doesn't count
  defp count_rows(html) do
    ("<table>" <> html <> "</table>")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tr[id^=customers-]:not(#customers-empty)")
    |> Enum.count()
  end

  describe "customer profile" do
    test "Support sees the account but can't change it or see invoices", %{conn: conn} do
      user = user_fixture()
      conn = log_in_staff(conn, staff_fixture(["support"]))

      {:ok, view, _html} = live(conn, ~p"/customers/#{user.id}")
      assert has_element?(view, "#customer-header")
      assert has_element?(view, "#customer-plan")
      assert has_element?(view, "#customer-usage")
      refute has_element?(view, "#customer-actions")
      refute has_element?(view, "#customer-invoices")
    end

    test "staff accounts don't open as customers", %{conn: conn} do
      admin = staff_fixture()
      conn = log_in_staff(conn, admin)
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/customers/#{admin.id}") end
    end

    test "extends the trial", %{conn: conn} do
      user = user_fixture()
      before = Billing.get_subscription(user.id).trial_ends_at

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/customers/#{user.id}")

      view |> element("#action-extend") |> render_click()
      view |> form("#customer-action-form", action: %{days: "7"}) |> render_submit()

      refute has_element?(view, "#customer-dialog")
      assert DateTime.diff(Billing.get_subscription(user.id).trial_ends_at, before, :day) == 7
      assert has_element?(view, "#plan-history")
    end

    test "gives a plan, then moves to Free", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/customers/#{user.id}")

      view |> element("#action-give") |> render_click()
      until = Date.utc_today() |> Date.add(10) |> Date.to_iso8601()

      view
      |> form("#customer-action-form", action: %{plan: "plus", until: until})
      |> render_submit()

      assert Billing.get_subscription(user.id).complimentary
      refute has_element?(view, "#action-extend")

      view |> element("#action-free") |> render_click()
      view |> form("#customer-action-form") |> render_submit()
      assert Billing.get_subscription(user.id).plan.slug == "free"
      refute has_element?(view, "#action-free")
    end

    test "shows errors in the dialog", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/customers/#{user.id}")

      view |> element("#action-gift") |> render_click()

      view
      |> form("#customer-action-form", action: %{months: "2", reason: " "})
      |> render_submit()

      assert has_element?(view, "#customer-action-error")
      assert has_element?(view, "#customer-dialog")
    end

    test "suspends and unsuspends", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/customers/#{user.id}")

      view |> element("#action-suspend") |> render_click()
      view |> form("#customer-action-form", action: %{reason: "Spam albums"}) |> render_submit()
      assert has_element?(view, "#suspension-note", "Spam albums")
      assert Keepsakes.Accounts.get_user(user.id).suspended_at

      view |> element("#action-unsuspend") |> render_click()
      view |> form("#customer-action-form") |> render_submit()
      refute has_element?(view, "#suspension-note")
      refute Keepsakes.Accounts.get_user(user.id).suspended_at
    end
  end
end
