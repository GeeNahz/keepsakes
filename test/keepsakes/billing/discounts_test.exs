defmodule Keepsakes.Billing.DiscountsTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.{Billing, FlutterwaveStub}
  alias Keepsakes.Billing.{DiscountCode, Discounts, Invoice, Quote}

  @return "http://localhost:4000/app/billing/return"

  setup do
    FlutterwaveStub.stub()
    scope = user_scope_fixture()
    %{scope: scope, user: scope.user}
  end

  defp code_fixture(attrs) do
    {:ok, code} =
      Discounts.create_code(
        Enum.into(attrs, %{code: "launch20", percent_off: 20, duration: "once"})
      )

    code
  end

  defp price(plan, interval \\ "month"), do: Billing.get_price!(plan, "NGN", interval)

  defp pay(scope, price, code \\ nil) do
    {:ok, {:redirect, link}} = Billing.start_checkout(scope, price, @return, code: code)
    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
    Repo.one!(from i in Invoice, where: i.status == "paid", order_by: [desc: i.number], limit: 1)
  end

  defp renew(user) do
    update_subscription(user,
      current_period_end: DateTime.add(DateTime.utc_now(:second), -1, :hour)
    )

    %{renewed: 1} = Billing.advance()

    Repo.one!(
      from i in Invoice,
        where: i.kind == "renewal" and i.status == "paid",
        order_by: [desc: i.number],
        limit: 1
    )
  end

  describe "codes" do
    test "are stored upper-case and matched however they're typed", %{user: user} do
      code = code_fixture(code: " launch20 ")
      assert code.code == "LAUNCH20"

      assert {:ok, %DiscountCode{code: "LAUNCH20"}} =
               Discounts.check("Launch20", user.id, price("plus"))

      assert DiscountCode.summary(code) == "20% off your first payment"
    end

    test "explain why they can't be used", %{user: user} do
      code_fixture(code: "OLD", expires_at: DateTime.add(DateTime.utc_now(:second), -60))

      code_fixture(code: "FULL", max_redemptions: 1)
      |> Ecto.Changeset.change(redemptions_count: 1)
      |> Repo.update!()

      code_fixture(code: "PROONLY", plan_slugs: ["pro"])
      code_fixture(code: "OFF", active: false)

      assert {:error, :not_found} = Discounts.check("NOPE", user.id, price("plus"))
      assert {:error, :not_found} = Discounts.check("OFF", user.id, price("plus"))
      assert {:error, :expired} = Discounts.check("OLD", user.id, price("plus"))
      assert {:error, :used_up} = Discounts.check("FULL", user.id, price("plus"))
      assert {:error, :wrong_plan} = Discounts.check("PROONLY", user.id, price("plus"))
      assert {:ok, _} = Discounts.check("PROONLY", user.id, price("pro"))
    end

    test "a repeating code needs its months" do
      assert {:error, changeset} =
               Discounts.create_code(%{code: "X1", percent_off: 10, duration: "repeating"})

      assert %{duration_months: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "at checkout" do
    test "a code takes its share off, rounded to whole naira", %{scope: scope} do
      code_fixture(code: "THIRD", percent_off: 33)

      assert {:ok,
              %Quote{
                discount_minor: 165_000,
                amount_minor: 335_000,
                discount_label: "THIRD · 33% off"
              }} =
               Billing.quote_price(scope, price("plus"), code: "third")
    end

    test "a used code is recorded, and can't be used twice", %{scope: scope, user: user} do
      code_fixture(code: "ONCE10", percent_off: 10)
      invoice = pay(scope, price("plus"), "ONCE10")

      assert {invoice.discount_minor, invoice.amount_minor} == {50_000, 450_000}
      assert Repo.get_by!(DiscountCode, code: "ONCE10").redemptions_count == 1
      assert {:error, :already_used} = Discounts.check("ONCE10", user.id, price("pro"))
    end

    test "a 100% code can't start a card plan", %{scope: scope} do
      code_fixture(code: "FREE", percent_off: 100, duration: "forever")

      assert {:error, {:code, :too_much}} =
               Billing.quote_price(scope, price("plus"), code: "FREE")
    end

    test "codes don't apply to changes booked for renewal", %{scope: scope} do
      code_fixture(code: "DOWN")
      pay(scope, price("pro"))
      assert {:error, {:code, :not_now}} = Billing.quote_price(scope, price("plus"), code: "DOWN")
    end
  end

  describe "at renewal" do
    test "once: only the first payment", %{scope: scope, user: user} do
      code_fixture(code: "FIRST", percent_off: 50)
      assert pay(scope, price("plus"), "FIRST").discount_minor == 250_000
      assert renew(user).discount_minor == 0
    end

    test "repeating: for its months, then full price", %{scope: scope, user: user} do
      code_fixture(code: "TWO", percent_off: 10, duration: "repeating", duration_months: 2)
      # Not on a trial, so periods start now
      update_subscription(user, trial_ends_at: nil)
      assert pay(scope, price("plus"), "TWO").discount_minor == 50_000

      # Second month: still inside the two months
      assert renew(user).discount_minor == 50_000

      # Past the two months
      update_subscription(user,
        current_period_end: DateTime.add(DateTime.utc_now(:second), 70, :day)
      )

      Billing.advance(DateTime.add(DateTime.utc_now(:second), 71, :day))

      latest =
        Repo.one!(
          from i in Invoice, where: i.kind == "renewal", order_by: [desc: i.number], limit: 1
        )

      assert latest.discount_minor == 0
    end

    test "forever: every renewal, and it shows on the subscription", %{scope: scope, user: user} do
      code_fixture(code: "ALWAYS", percent_off: 25, duration: "forever")
      pay(scope, price("plus"), "ALWAYS")
      assert renew(user).discount_minor == 125_000

      sub = Billing.get_subscription_details(scope)
      assert sub.discount_redemption.discount_code.code == "ALWAYS"
    end
  end

  test "the mix task creates codes" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Tasks.Keepsakes.Discount.Create.run(
      ~w(spring --percent 30 --duration repeating --months 3 --plans plus,pro --expires 2027-03-31)
    )

    assert_received {:mix_shell, :info, ["Created SPRING: 30% off for 3 months"]}

    code = Repo.get_by!(DiscountCode, code: "SPRING")
    assert code.plan_slugs == ["plus", "pro"]
    assert code.expires_at == ~U[2027-03-31 23:59:59Z]
  end
end
