defmodule Keepsakes.Billing.ReferralsTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures

  alias Keepsakes.{Accounts, Billing, FlutterwaveStub}
  alias Keepsakes.Accounts.Scope

  @return "http://localhost:4000/app/billing/return"

  setup do
    FlutterwaveStub.stub()
    inviter = user_fixture()
    assert_email_sent(subject: "Confirm your Keepsake account")
    %{inviter: inviter}
  end

  defp invited(inviter, code \\ nil) do
    {:ok, user} =
      Accounts.register_user(valid_user_attributes(),
        referral_code: code || String.downcase(inviter.referral_code)
      )

    user
  end

  defp pay(user, plan \\ "plus") do
    scope = Scope.for_user(Accounts.get_user!(user.id))
    price = Billing.get_price!(plan, "NGN", "month")
    {:ok, {:redirect, link}} = Billing.start_checkout(scope, price, @return)
    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
  end

  test "every user gets an invite code, and sign-ups remember who invited them", %{
    inviter: inviter
  } do
    assert inviter.referral_code =~ ~r/^[A-Z2-9]{8}$/
    assert invited(inviter).referred_by_id == inviter.id

    {:ok, stranger} = Accounts.register_user(valid_user_attributes(), referral_code: "NOPE1234")
    assert is_nil(stranger.referred_by_id)

    assert %{joined: 1, paid: 0, banked: 0} = Billing.referrals(Scope.for_user(inviter))
  end

  test "a trial inviter banks the month and spends it on their first period", %{inviter: inviter} do
    friend = invited(inviter)
    pay(friend)

    # The friend's receipt, then the inviter's reward
    assert_email_sent(&(&1.subject =~ "Your Keepsake receipt"))
    assert_email_sent(subject: "You earned a free month of Keepsake")
    assert %{joined: 1, paid: 1, banked: 1} = Billing.referrals(Scope.for_user(inviter))

    # The banked month lengthens the inviter's first paid period
    scope = Scope.for_user(Accounts.get_user!(inviter.id))
    trial_end = Billing.get_subscription(inviter.id).trial_ends_at
    {:ok, quote} = Billing.quote_price(scope, Billing.get_price!("plus", "NGN", "month"))
    assert quote.free_months == 1
    assert DateTime.compare(quote.period_end, DateTime.shift(trial_end, month: 2)) == :eq

    pay(inviter)
    sub = Billing.get_subscription(inviter.id)
    assert DateTime.compare(sub.current_period_end, DateTime.shift(trial_end, month: 2)) == :eq
    assert Accounts.get_user!(inviter.id).free_months_banked == 0
  end

  test "a paying inviter's period is extended by a month, once per friend", %{inviter: inviter} do
    pay(inviter)
    before = Billing.get_subscription(inviter.id).current_period_end

    friend = invited(inviter)
    pay(friend)
    after_first = Billing.get_subscription(inviter.id).current_period_end
    assert DateTime.compare(after_first, DateTime.shift(before, month: 1)) == :eq

    # The friend's later payments (an upgrade) don't reward again
    pay(friend, "pro")
    assert Billing.get_subscription(inviter.id).current_period_end == after_first
    assert %{paid: 1} = Billing.referrals(Scope.for_user(inviter))
  end
end
