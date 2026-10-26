defmodule KeepsakesWeb.AdminFinanceLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Billing, FlutterwaveStub, Repo}
  alias Keepsakes.Billing.{DiscountCode, Plan, Refund}

  setup do
    FlutterwaveStub.stub()
    :ok
  end

  describe "plans" do
    setup %{conn: conn}, do: %{conn: log_in_staff(conn, staff_fixture())}

    test "lists plans and changes a price from the form", %{conn: conn} do
      plus = Repo.get_by!(Plan, slug: "plus")
      {:ok, view, _html} = live(conn, ~p"/plans")
      assert has_element?(view, "#plans-#{plus.id}")

      {:ok, view, _html} = live(conn, ~p"/plans/#{plus.id}")
      assert has_element?(view, "#plan-prices")

      view
      |> form("#plan-form", plan: %{prices: %{"NGN_month" => "8000"}})
      |> render_submit()

      assert_redirect(view, ~p"/plans")
      assert Billing.get_price!("plus", "NGN", "month").amount_minor == 800_000
    end

    test "creates a plan", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plans/new")

      view
      |> form("#plan-form",
        plan: %{name: "Family", slug: "family", prices: %{"USD_month" => "9"}}
      )
      |> render_submit()

      assert_redirect(view, ~p"/plans")
      family = Repo.get_by!(Plan, slug: "family") |> Repo.preload(:prices)
      refute family.public
      assert [%{currency: "USD", amount_minor: 900}] = family.prices
    end

    test "Free has no prices or visibility to edit", %{conn: conn} do
      free = Repo.get_by!(Plan, slug: "free")
      {:ok, view, _html} = live(conn, ~p"/plans/#{free.id}")
      refute has_element?(view, "#plan-prices")
      refute has_element?(view, "#plan_public")
      assert has_element?(view, "#plan-features")
    end

    test "shows a bad price", %{conn: conn} do
      plus = Repo.get_by!(Plan, slug: "plus")
      {:ok, view, _html} = live(conn, ~p"/plans/#{plus.id}")

      html =
        view |> form("#plan-form", plan: %{prices: %{"NGN_month" => "lots"}}) |> render_submit()

      assert html =~ "must be an amount"
    end
  end

  describe "discount codes" do
    setup %{conn: conn}, do: %{conn: log_in_staff(conn, staff_fixture())}

    test "creates and edits a code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/discounts/new")

      view
      |> form("#discount-form", discount: %{code: "launch", percent_off: "25", duration: "once"})
      |> render_submit()

      assert_redirect(view, ~p"/discounts")
      code = Repo.get_by!(DiscountCode, code: "LAUNCH")

      {:ok, view, _html} = live(conn, ~p"/discounts")
      assert has_element?(view, "#discounts-#{code.id}")

      {:ok, view, _html} = live(conn, ~p"/discounts/#{code.id}")
      view |> form("#discount-form", discount: %{active: "false"}) |> render_submit()
      refute Repo.reload!(code).active
    end

    test "a used code's terms can't be edited", %{conn: conn} do
      {:ok, code} =
        Keepsakes.Billing.Discounts.create_code(%{
          code: "USED",
          percent_off: 10,
          duration: "once"
        })

      code |> Ecto.Changeset.change(redemptions_count: 2) |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/discounts/#{code.id}")
      assert has_element?(view, "#discount_percent_off[disabled]")
    end
  end

  describe "finance" do
    setup %{conn: conn} do
      user = user_fixture()
      invoice = pay_fixture(user)

      %{
        conn: log_in_staff(conn, staff_fixture()),
        user: user,
        invoice: invoice,
        payment: hd(invoice.payments)
      }
    end

    test "overview, payments and invoice pages", %{conn: conn, invoice: invoice, user: user} do
      {:ok, view, _html} = live(conn, ~p"/finance")
      assert has_element?(view, "#stat-this-month-ngn")
      assert has_element?(view, "#revenue-ngn svg")
      assert has_element?(view, "#revenue-by-plan", "Plus")

      {:ok, view, _html} = live(conn, ~p"/finance/payments")
      assert has_element?(view, "#payments", invoice.number)

      view |> form("#payment-filters", payments: %{status: "failed"}) |> render_change()
      refute has_element?(view, "#payments", invoice.number)

      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
      assert has_element?(view, "#invoice-amounts")
      assert has_element?(view, "#invoice-customer", user.email)
    end

    test "refunds part of a payment from the invoice page", %{
      conn: conn,
      invoice: invoice,
      payment: payment,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")

      view |> element("#refund-#{payment.id}") |> render_click()
      assert has_element?(view, "#refund-dialog")

      view
      |> form("#refund-form",
        refund: %{amount: "1000", reason: "Goodwill", plan_action: "end_now"}
      )
      |> render_submit()

      refute has_element?(view, "#refund-dialog")
      assert [%Refund{amount_minor: 100_000}] = Repo.all(Refund)
      assert has_element?(view, "#invoice-refunds", "Goodwill")
      assert Billing.get_subscription(user.id).plan.slug == "free"
    end

    test "shows the gateway's refusal", %{conn: conn, invoice: invoice, payment: payment} do
      FlutterwaveStub.stub(refund: :failed)
      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")

      view |> element("#refund-#{payment.id}") |> render_click()

      view
      |> form("#refund-form", refund: %{amount: "1000", reason: "x", plan_action: "end_now"})
      |> render_submit()

      assert has_element?(view, "#refund-error", "refused")
      assert [%Refund{status: "failed", id: id}] = Repo.all(Refund)
      assert has_element?(view, "#refund-row-#{id}", "Failed")
    end

    test "a deleted customer's invoice still opens", %{conn: conn, invoice: invoice, user: user} do
      Repo.delete!(user)
      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
      assert has_element?(view, "#deleted-customer")
      assert has_element?(view, "#invoice-customer", user.email)
    end

    test "no customer link when the payer is staff", %{conn: conn, invoice: invoice, user: user} do
      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
      assert has_element?(view, ~s(#invoice-customer a[href="/customers/#{user.id}"]))

      {:ok, _} = Keepsakes.Staff.grant(:system, user.email, [role("support").id])
      {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
      refute has_element?(view, "#invoice-customer a")
    end

    test "exports payments as CSV", %{conn: conn, invoice: invoice} do
      conn = get(conn, ~p"/finance/export/payments.csv")
      assert response_content_type(conn, :csv)
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "keepsake-payments-"
      assert conn.resp_body =~ invoice.number
    end
  end

  describe "permissions" do
    test "Finance sees finance but not plans or discounts", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["finance"]))

      {:ok, view, _html} = live(conn, ~p"/finance")
      assert has_element?(view, "#admin-nav-finance")
      refute has_element?(view, "#admin-nav-plans")
      refute has_element?(view, "#admin-nav-discounts")

      assert_error_sent 403, fn -> get(conn, ~p"/plans") end
      assert_error_sent 403, fn -> get(conn, ~p"/discounts") end
    end

    test "Support can't see finance or export", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["support"]))
      assert_error_sent 403, fn -> get(conn, ~p"/finance") end
      assert_error_sent 403, fn -> get(conn, ~p"/finance/export/payments.csv") end
    end
  end
end
