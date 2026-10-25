defmodule Keepsakes.BillingTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Billing
  alias Keepsakes.Billing.{Price, SubscriptionEvent}

  describe "plans" do
    test "Free, Plus and Pro are public with NGN and USD prices; the trial is hidden" do
      plans = Billing.list_public_plans()
      assert Enum.map(plans, & &1.slug) == ["free", "plus", "pro"]

      plus = Enum.find(plans, &(&1.slug == "plus"))
      assert %Price{amount_minor: 500_000} = Billing.price(plus, "NGN", "month")
      assert %Price{amount_minor: 5_000} = Billing.price(plus, "USD", "year")
      assert Billing.price(hd(plans), "NGN", "month") == nil
    end

    test "prices format with the currency symbol" do
      assert Price.format("NGN", 500_000) == "₦5,000"
      assert Price.format("NGN", 12_000_000) == "₦120,000"
      assert Price.format("USD", 1_250) == "$12.50"
    end
  end

  describe "registration" do
    test "starts a 60-day trial on Pro features" do
      user = user_fixture()
      subscription = Billing.get_subscription(user.id)

      assert subscription.status == "trialing"
      assert subscription.plan.slug == "trial"
      assert Billing.days_until(subscription.trial_ends_at) == 60
      assert Billing.status_label(subscription) == "Free trial · 60 days left"

      assert [%SubscriptionEvent{kind: "trial_started"}] =
               Repo.all(from e in SubscriptionEvent, where: e.subscription_id == ^subscription.id)
    end
  end

  describe "advance/1" do
    setup do
      user = user_fixture()
      # The fixture's sign-in email, so later assertions see only ours
      assert_email_sent(subject: "Confirm your Keepsake account")
      %{user: user, now: DateTime.utc_now(:second)}
    end

    test "reminds once, a week before the trial ends", %{user: user, now: now} do
      update_subscription(user, trial_ends_at: DateTime.add(now, 6, :day))

      assert %{reminders: 1, grace: 0, free: 0} = Billing.advance(now)
      assert_email_sent(fn email -> assert email.subject =~ "Your Keepsake trial ends on " end)
      assert %{reminders: 0} = Billing.advance(now)
      refute_email_sent()
    end

    test "trial → grace with full access → Free", %{user: user, now: now} do
      update_subscription(user, trial_ends_at: DateTime.add(now, -1, :minute))

      assert %{grace: 1} = Billing.advance(now)
      subscription = Billing.get_subscription(user.id)
      assert subscription.status == "grace"
      assert subscription.plan.slug == "trial"
      assert Billing.days_until(subscription.grace_ends_at, now) == 7
      assert_email_sent(subject: "Your Keepsake trial has ended")

      assert %{grace: 0, free: 0} = Billing.advance(now)

      later = DateTime.add(now, 8, :day)
      assert %{free: 1} = Billing.advance(later)
      subscription = Billing.get_subscription(user.id)
      assert {subscription.status, subscription.plan.slug} == {"active", "free"}
      assert Billing.status_label(subscription) == "Free plan"
      assert_email_sent(subject: "Your Keepsake account is now on the Free plan")

      kinds =
        Repo.all(
          from e in SubscriptionEvent,
            where: e.subscription_id == ^subscription.id,
            order_by: e.inserted_at,
            select: {e.kind, e.to_plan}
        )

      assert {"grace_started", "trial"} in kinds
      assert {"moved_to_free", "free"} in kinds
    end

    test "leaves trials that aren't due alone", %{now: now} do
      assert %{reminders: 0, grace: 0, free: 0} = Billing.advance(now)
    end
  end

  test "current_plan falls back to Free without a subscription" do
    user = user_fixture()
    Repo.delete_all(from s in Keepsakes.Billing.Subscription, where: s.user_id == ^user.id)
    assert Billing.current_plan(user.id).slug == "free"
  end
end
