defmodule KeepsakesWeb.BillingCheckoutTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Keepsakes.{Billing, FlutterwaveStub, Repo}
  alias Keepsakes.Billing.{Gateways.Flutterwave, Payment}

  setup :register_and_log_in_user

  setup do
    FlutterwaveStub.stub()
    :ok
  end

  defp live_billing(conn) do
    {:ok, lv, _html} = live(conn, ~p"/billing")
    Req.Test.allow(Flutterwave, self(), lv.pid)
    lv
  end

  test "choosing a plan shows the charge, then goes to Flutterwave", %{conn: conn} do
    lv = live_billing(conn)

    lv |> element("#choose-plus") |> render_click()
    assert has_element?(lv, "#checkout-dialog #quote-amount", "₦5,000")
    assert has_element?(lv, "#quote-summary", "remaining trial days are included")

    assert {:error, {:redirect, %{to: "https://checkout.flutterwave.test/pay/" <> tx_ref}}} =
             lv |> element("#confirm-plan") |> render_click()

    assert Repo.get_by!(Payment, tx_ref: tx_ref).amount_minor == 500_000
  end

  test "the return page confirms and the page shows the plan", %{conn: conn, scope: scope} do
    {:ok, {:redirect, link}} =
      Billing.start_checkout(scope, Billing.get_price!("plus", "NGN", "month"), "http://x")

    "https://checkout.flutterwave.test/pay/" <> tx_ref = link

    conn =
      get(
        conn,
        ~p"/billing/return?status=successful&tx_ref=#{tx_ref}&transaction_id=fw-#{tx_ref}"
      )

    assert redirected_to(conn) == "/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Payment received"

    lv = live_billing(conn)
    assert has_element?(lv, "#current-plan-name", "Plus")
    assert has_element?(lv, "#card-on-file", "Visa •••• 4242")
    assert has_element?(lv, "#billing-details", "Renews on")
    assert has_element?(lv, "#choose-plus", "Your plan")
    assert has_element?(lv, "#choose-pro", "Upgrade to Pro")
    assert has_element?(lv, "#invoices a", "Receipt")

    [invoice] = Billing.list_invoices(scope)
    {:ok, receipt, _html} = live(conn, ~p"/billing/invoices/#{invoice.id}")
    assert has_element?(receipt, "#receipt-number", invoice.number)
    assert has_element?(receipt, "#receipt-amount", "₦5,000")
  end

  test "a cancelled checkout charges nothing", %{conn: conn, scope: scope} do
    {:ok, {:redirect, link}} =
      Billing.start_checkout(scope, Billing.get_price!("plus", "NGN", "month"), "http://x")

    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    conn = get(conn, ~p"/billing/return?status=cancelled&tx_ref=#{tx_ref}")

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "haven't been charged"
    assert Billing.get_subscription(scope).plan.slug == "trial"
  end

  test "someone else's payment reference is refused", %{conn: conn} do
    other = Keepsakes.AccountsFixtures.user_scope_fixture()

    {:ok, {:redirect, link}} =
      Billing.start_checkout(other, Billing.get_price!("plus", "NGN", "month"), "http://x")

    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    conn = get(conn, ~p"/billing/return?status=successful&tx_ref=#{tx_ref}")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't find that payment"
    assert Billing.get_subscription(other).plan.slug == "trial"
  end

  test "cancel and keep the plan", %{conn: conn, scope: scope} do
    {:ok, {:redirect, link}} =
      Billing.start_checkout(scope, Billing.get_price!("plus", "NGN", "month"), "http://x")

    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)

    lv = live_billing(conn)
    lv |> element("#cancel-plan") |> render_click()
    assert has_element?(lv, "#current-plan-status", "Ends on")
    assert has_element?(lv, "#billing-details", "Ends on")

    lv |> element("#resume-plan") |> render_click()
    assert has_element?(lv, "#cancel-plan")
  end

  describe "POST /webhooks/flutterwave" do
    test "needs the secret hash", %{conn: conn} do
      conn = post(conn, ~p"/webhooks/flutterwave", FlutterwaveStub.webhook("ks-x"))
      assert response(conn, 401)
    end

    test "stores the event and answers 200", %{conn: conn} do
      conn =
        conn
        |> put_req_header("verif-hash", "test-webhook-hash")
        |> post(~p"/webhooks/flutterwave", FlutterwaveStub.webhook("ks-x"))

      assert response(conn, 200)
      assert Repo.aggregate(Keepsakes.Billing.PaymentEvent, :count) == 1
    end
  end
end
