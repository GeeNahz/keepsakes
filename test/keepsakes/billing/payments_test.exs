defmodule Keepsakes.Billing.PaymentsTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.{Billing, FlutterwaveStub}
  alias Keepsakes.Billing.{Invoice, Payment, PaymentEvent, Payments, Quote}

  @return "http://localhost:4000/billing/return"

  setup do
    FlutterwaveStub.stub()
    user = user_fixture()
    assert_email_sent(subject: "Confirm your Keepsake account")
    %{user: user, scope: Keepsakes.Accounts.Scope.for_user(user)}
  end

  defp assert_receipt,
    do: assert_email_sent(&assert(&1.subject =~ "Your Keepsake receipt KS-"))

  defp price(plan, currency \\ "NGN", interval \\ "month"),
    do: Billing.get_price!(plan, currency, interval)

  # Checks out `price` and confirms it as Flutterwave would on return
  defp pay(scope, price) do
    {:ok, {:redirect, link}} = Billing.start_checkout(scope, price, @return)
    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
    tx_ref
  end

  describe "quotes" do
    test "paying during the trial keeps its remaining days", %{scope: scope, user: user} do
      now = DateTime.utc_now(:second)
      trial_end = Billing.get_subscription(user.id).trial_ends_at

      assert {:ok, %Quote{mode: :checkout, amount_minor: 500_000, credit_minor: 0} = quote} =
               Billing.quote_price(scope, price("plus"))

      assert DateTime.compare(quote.period_end, DateTime.shift(trial_end, month: 1)) == :eq
      assert DateTime.after?(quote.period_end, DateTime.shift(now, month: 2))
    end

    test "upgrades credit unused days; downgrades wait for renewal", %{scope: scope, user: user} do
      pay(scope, price("plus"))
      # Halfway through a paid period, trial long over
      sub = Billing.get_subscription(user.id)
      start = DateTime.add(DateTime.utc_now(:second), -15, :day)

      update_subscription(user,
        trial_ends_at: DateTime.add(start, -30, :day),
        current_period_start: start,
        current_period_end: DateTime.add(start, 30, :day)
      )

      assert {:ok, %Quote{mode: :checkout, credit_minor: credit, amount_minor: amount}} =
               Billing.quote_price(scope, price("pro"))

      # Half of ₦5,000, in whole naira
      assert credit in 249_900..250_000
      assert rem(credit, 100) == 0
      assert amount == 1_200_000 - credit

      assert {:ok, %Quote{mode: :checkout, credit_minor: credit}} =
               Billing.quote_price(scope, price("plus", "NGN", "year"))

      assert credit > 0

      assert {:error, :current_plan} = Billing.quote_price(scope, price("plus"))
      assert sub.plan.slug == "plus"
    end

    test "upgrading while trial days remain keeps them and credits the full price", %{
      scope: scope,
      user: user
    } do
      trial_end = Billing.get_subscription(user.id).trial_ends_at
      pay(scope, price("plus"))

      assert {:ok, %Quote{credit_minor: 500_000, amount_minor: 700_000} = quote} =
               Billing.quote_price(scope, price("pro"))

      assert DateTime.compare(quote.period_end, DateTime.shift(trial_end, month: 1)) == :eq
    end

    test "moving down is scheduled", %{scope: scope} do
      pay(scope, price("pro"))
      assert {:ok, %Quote{mode: :scheduled}} = Billing.quote_price(scope, price("plus"))
      # Same plan in another currency: from the next renewal
      assert {:ok, %Quote{mode: :scheduled}} = Billing.quote_price(scope, price("pro", "USD"))
    end
  end

  describe "checkout and confirming" do
    test "a confirmed payment starts the plan, saves the card and emails a receipt", %{
      scope: scope,
      user: user
    } do
      {:ok, {:redirect, link}} = Billing.start_checkout(scope, price("plus"), @return)
      "https://checkout.flutterwave.test/pay/" <> tx_ref = link
      assert_received {:flutterwave, "POST", "/v3/payments", %{"amount" => 5000.0}}

      payment = Repo.get_by!(Payment, tx_ref: tx_ref) |> Repo.preload(:invoice)
      assert payment.status == "pending"
      assert payment.invoice.status == "open"
      assert payment.invoice.number =~ ~r/^KS-\d{6}$/

      assert {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)

      sub = Billing.get_subscription(user.id)
      assert {sub.status, sub.plan.slug} == {"active", "plus"}
      assert sub.current_period_end
      assert Billing.payment_method(scope).last4 == "4242"
      assert [%Invoice{status: "paid"}] = Billing.list_invoices(scope)
      assert_email_sent(subject: "Your Keepsake receipt " <> payment.invoice.number)

      # Confirming again (webhook after return) changes nothing
      assert {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
      refute_email_sent()
    end

    test "a short payment is not applied", %{scope: scope, user: user} do
      FlutterwaveStub.stub(amount_minor: 100)
      {:ok, {:redirect, link}} = Billing.start_checkout(scope, price("plus"), @return)
      "https://checkout.flutterwave.test/pay/" <> tx_ref = link

      assert {:error, :mismatch} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
      assert Billing.get_subscription(user.id).plan.slug == "trial"
      assert Repo.get_by!(Payment, tx_ref: tx_ref).status == "failed"
    end

    test "cancelling at checkout voids the invoice", %{scope: scope} do
      {:ok, {:redirect, link}} = Billing.start_checkout(scope, price("plus"), @return)
      "https://checkout.flutterwave.test/pay/" <> tx_ref = link

      :ok = Billing.abandon(tx_ref)
      assert Repo.get_by!(Payment, tx_ref: tx_ref).status == "failed"
      assert Billing.list_invoices(scope) == []
    end

    test "the gateway being down is reported", %{scope: scope} do
      FlutterwaveStub.stub(checkout: :down)

      assert {:error, :gateway_unavailable} =
               Billing.start_checkout(scope, price("plus"), @return)
    end

    test "a downgrade is booked and can be dropped", %{scope: scope, user: user} do
      pay(scope, price("pro"))
      assert {:ok, {:scheduled, _}} = Billing.start_checkout(scope, price("plus"), @return)
      assert Billing.get_subscription_details(scope).pending_price.plan.slug == "plus"

      assert {:ok, _} = Billing.cancel_scheduled_change(scope)
      assert Billing.get_subscription(user.id).plan.slug == "pro"
      refute Billing.get_subscription_details(scope).pending_price
    end
  end

  describe "webhooks" do
    test "are checked, stored once and confirmed in the background", %{scope: scope, user: user} do
      {:ok, {:redirect, link}} = Billing.start_checkout(scope, price("plus"), @return)
      "https://checkout.flutterwave.test/pay/" <> tx_ref = link
      body = FlutterwaveStub.webhook(tx_ref)

      assert {:error, :invalid} = Payments.receive_webhook([{"verif-hash", "wrong"}], body)
      assert :ok = Payments.receive_webhook([{"verif-hash", "test-webhook-hash"}], body)
      assert :ok = Payments.receive_webhook([{"verif-hash", "test-webhook-hash"}], body)
      assert Repo.aggregate(PaymentEvent, :count) == 1

      assert %{success: 1} = Oban.drain_queue(queue: :billing)
      assert Billing.get_subscription(user.id).plan.slug == "plus"
      assert Repo.one!(PaymentEvent).processed_at
    end
  end

  describe "renewals" do
    setup %{scope: scope, user: user} do
      pay(scope, price("plus"))
      assert_receipt()
      ended = DateTime.add(DateTime.utc_now(:second), -1, :hour)
      update_subscription(user, current_period_end: ended)
      %{ended: ended}
    end

    test "charge the saved card and extend the period", %{user: user, ended: ended} do
      assert %{renewed: 1} = Billing.advance()

      assert_received {:flutterwave, "POST", "/v3/tokenized-charges",
                       %{"token" => "flw-t1nf-test-token"}}

      sub = Billing.get_subscription(user.id)
      assert sub.status == "active"
      assert DateTime.compare(sub.current_period_start, ended) == :eq
      assert DateTime.compare(sub.current_period_end, DateTime.shift(ended, month: 1)) == :eq
      assert_receipt()
    end

    test "failures retry on days 1, 3 and 5, then grace, then Free", %{user: user} do
      FlutterwaveStub.stub(token_charge: :failed)
      now = DateTime.utc_now(:second)

      assert %{renewed: 0} = Billing.advance(now)
      sub = Billing.get_subscription(user.id)
      assert {sub.status, sub.plan.slug} == {"past_due", "plus"}
      assert Billing.days_until(sub.next_retry_at, now) == 1
      assert_email_sent(subject: "We couldn't renew your Keepsake plan")

      for {day, retry_in} <- [{1, 2}, {3, 2}] do
        at = DateTime.add(now, day, :day)
        Billing.advance(at)
        sub = Billing.get_subscription(user.id)
        assert sub.status == "past_due"
        assert Billing.days_until(sub.next_retry_at, at) == retry_in
      end

      Billing.advance(DateTime.add(now, 5, :day))
      sub = Billing.get_subscription(user.id)
      assert {sub.status, sub.plan.slug} == {"grace", "plus"}
      assert Billing.status_label(sub) =~ "Payment failed"
      assert_email_sent(subject: "Action needed: your Keepsake plan is about to end")

      Billing.advance(DateTime.add(now, 13, :day))
      sub = Billing.get_subscription(user.id)
      assert {sub.status, sub.plan.slug} == {"active", "free"}
      assert Repo.all(from i in Invoice, where: i.status == "open") == []
    end

    test "a booked downgrade applies at renewal", %{scope: scope, user: user} do
      update_subscription(user,
        current_period_end: DateTime.add(DateTime.utc_now(:second), 3, :day)
      )

      {:ok, {:scheduled, _}} = Billing.start_checkout(scope, price("plus", "USD"), @return)

      update_subscription(user,
        current_period_end: DateTime.add(DateTime.utc_now(:second), -1, :hour)
      )

      assert %{renewed: 1} = Billing.advance()

      assert_received {:flutterwave, "POST", "/v3/tokenized-charges",
                       %{"currency" => "USD", "amount" => 5.0}}

      sub = Billing.get_subscription_details(scope)
      assert sub.price.currency == "USD"
      refute sub.pending_price
    end

    test "cancelled plans move to Free when the period ends", %{scope: scope, user: user} do
      update_subscription(user,
        current_period_end: DateTime.add(DateTime.utc_now(:second), 3, :day)
      )

      assert {:ok, _} = Billing.cancel(scope)
      assert Billing.status_label(Billing.get_subscription(user.id)) =~ "Plus · ends on"

      assert {:ok, _} = Billing.resume(scope)
      assert {:ok, _} = Billing.cancel(scope)

      assert %{cancelled: 1, renewed: 0} =
               Billing.advance(DateTime.add(DateTime.utc_now(:second), 4, :day))

      assert Billing.get_subscription(user.id).plan.slug == "free"
      refute_received {:flutterwave, "POST", "/v3/tokenized-charges", _}
    end

    test "pending renewal charges are confirmed later", %{user: user} do
      FlutterwaveStub.stub(token_charge: :pending, charge: :pending)
      assert %{renewed: 0} = Billing.advance()
      assert Billing.get_subscription(user.id).status == "active"

      # Not charged again while one is in flight
      assert %{renewed: 0} = Billing.advance()
      assert Repo.aggregate(from(p in Payment, where: p.status == "pending"), :count) == 1

      FlutterwaveStub.stub(charge: :successful)

      assert %{confirmed: 1} =
               Billing.advance(DateTime.add(DateTime.utc_now(:second), 20, :minute))

      assert DateTime.after?(
               Billing.get_subscription(user.id).current_period_end,
               DateTime.utc_now()
             )
    end
  end
end
