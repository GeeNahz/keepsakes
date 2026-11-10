defmodule Keepsakes.FinanceTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Accounts, Audit, Billing, Finance, FlutterwaveStub}
  alias Keepsakes.Billing.{Invoice, Payment, Refund}
  alias Keepsakes.Staff.Forbidden

  setup do
    FlutterwaveStub.stub()
    admin = staff_scope_fixture()
    user = user_fixture()
    invoice = pay_fixture(user)
    flush_emails()
    %{admin: admin, user: user, invoice: invoice, payment: hd(invoice.payments)}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "record retention" do
    test "purging a deleted account keeps its invoices and payments", %{
      user: user,
      invoice: invoice
    } do
      {:ok, _user, _tokens} = Accounts.request_deletion(user)
      later = DateTime.add(DateTime.utc_now(:second), Accounts.deletion_grace_days() + 1, :day)
      assert Accounts.purge_deleted(later) == 1
      refute Accounts.get_user(user.id)

      kept = Repo.get!(Invoice, invoice.id)
      assert kept.user_id == nil
      assert kept.billing_email == user.email
      assert kept.billing_name == Keepsakes.Accounts.User.full_name(user)

      assert [%Payment{user_id: nil, status: "successful"}] =
               Repo.all(from p in Payment, where: p.invoice_id == ^invoice.id)
    end
  end

  describe "overview/2" do
    test "revenue is payments minus refunds, per currency", %{admin: admin, payment: payment} do
      amount = payment.amount_minor
      assert Finance.overview(admin).this_month == %{"NGN" => amount, "USD" => 0}

      {:ok, _} =
        Finance.refund(admin, payment, 10_000, %{
          "reason" => "Goodwill",
          "plan_action" => "end_at_period_end"
        })

      overview = Finance.overview(admin)
      assert overview.this_month["NGN"] == amount - 10_000
      assert overview.refunds_this_month["NGN"] == 10_000
      assert [{"Plus", "NGN", net}] = overview.by_plan
      assert net == amount - 10_000
      assert {_month, ^net} = List.last(overview.monthly["NGN"])
      assert length(overview.monthly["NGN"]) == 12
    end

    test "needs finance.view" do
      assert_raise Forbidden, fn -> Finance.overview(staff_scope_fixture(["support"])) end
    end
  end

  describe "list_payments/3" do
    test "filters by status, currency, search and dates", %{
      admin: admin,
      user: user,
      invoice: invoice
    } do
      ids = fn filters ->
        admin |> Finance.list_payments(filters) |> elem(0) |> Enum.map(& &1.invoice.id)
      end

      assert invoice.id in ids.(%{})
      assert invoice.id in ids.(%{"status" => "successful"})
      refute invoice.id in ids.(%{"status" => "failed"})
      refute invoice.id in ids.(%{"currency" => "USD"})
      assert invoice.id in ids.(%{"q" => String.upcase(user.email)})
      assert invoice.id in ids.(%{"q" => invoice.number})
      today = Date.to_iso8601(Date.utc_today())
      assert invoice.id in ids.(%{"from" => today, "to" => today})
      refute invoice.id in ids.(%{"to" => "2020-01-01"})
      refute invoice.id in ids.(%{"status" => "refunded"})
    end
  end

  describe "refund/4" do
    test "a partial refund keeps the plan until the period ends", %{
      admin: admin,
      user: user,
      payment: payment,
      invoice: invoice
    } do
      assert {:ok, refund} =
               Finance.refund(admin, payment, 20_000, %{
                 "reason" => "Charged twice",
                 "plan_action" => "end_at_period_end"
               })

      assert refund.amount_minor == 20_000
      path = "/v3/transactions/#{payment.gateway_id}/refund"
      assert_received {:flutterwave, "POST", ^path, %{"amount" => 200.0}}

      sub = Billing.get_subscription(user.id)
      assert sub.plan.slug == "plus"
      assert sub.cancel_at_period_end

      assert Finance.refundable(payment) == payment.amount_minor - 20_000
      assert_email_sent(subject: "Refund for Keepsake invoice #{invoice.number}")

      assert [%{changes: %{"amount" => 20_000, "plan" => "end_at_period_end"}}] =
               Audit.list(admin, %{"action" => "payment.refunded"})
    end

    test "a full refund can end the plan now", %{admin: admin, user: user, payment: payment} do
      assert {:ok, _} =
               Finance.refund(admin, payment, payment.amount_minor, %{
                 "reason" => "Didn't mean to buy",
                 "plan_action" => "end_now"
               })

      assert Billing.get_subscription(user.id).plan.slug == "free"
      assert Finance.refundable(payment) == 0
    end

    test "refuses more than what's left, bad input and other people's mistakes", %{
      admin: admin,
      payment: payment
    } do
      opts = %{"reason" => "x", "plan_action" => "end_now"}

      assert {:error, {:too_much, left}} =
               Finance.refund(admin, payment, payment.amount_minor + 1, opts)

      assert left == payment.amount_minor
      assert {:error, :invalid_amount} = Finance.refund(admin, payment, 0, opts)

      assert {:error, :reason_required} =
               Finance.refund(admin, payment, 100, %{opts | "reason" => " "})

      assert {:error, :plan_action_required} =
               Finance.refund(admin, payment, 100, %{opts | "plan_action" => "?"})

      refute Repo.exists?(Refund)
    end

    test "records nothing when the gateway refuses", %{admin: admin, user: user, payment: payment} do
      FlutterwaveStub.stub(refund: :failed)

      assert {:error, {:gateway, message}} =
               Finance.refund(admin, payment, 10_000, %{
                 "reason" => "x",
                 "plan_action" => "end_now"
               })

      assert message =~ "Refund amount exceeds balance"

      # Kept as a failed attempt; it doesn't count as money out or hold anything back
      assert [%Refund{status: "failed", failure_reason: reason}] = Repo.all(Refund)
      assert reason =~ "Refund amount exceeds balance"
      assert Finance.refundable(payment) == payment.amount_minor
      assert Finance.overview(admin).refunds_this_month["NGN"] == 0
      assert Billing.get_subscription(user.id).plan.slug == "plus"
      refute_email_sent()
    end

    test "a refund waiting on the gateway holds back what can be refunded", %{
      admin: admin,
      payment: payment,
      invoice: invoice
    } do
      Repo.insert!(%Refund{
        payment_id: payment.id,
        invoice_id: invoice.id,
        amount_minor: payment.amount_minor - 100,
        currency: "NGN",
        reason: "In flight",
        plan_action: "end_now",
        staff_email: admin.user.email
      })

      assert Finance.refundable(payment) == 100

      assert {:error, {:too_much, 100}} =
               Finance.refund(admin, payment, 200, %{"reason" => "x", "plan_action" => "end_now"})

      # Not money out until the gateway confirms
      assert Finance.overview(admin).refunds_this_month["NGN"] == 0
    end

    test "is recorded even before the plan module has been used", %{
      admin: admin,
      payment: payment
    } do
      # The bug found in the walk-through: plan choices are mapped, not turned into atoms
      assert {:ok, %Refund{status: "succeeded"}} =
               Finance.refund(admin, payment, 100, %{
                 "reason" => "x",
                 "plan_action" => "end_at_period_end"
               })
    end

    test "works for a deleted account, emailing the kept address", %{
      admin: admin,
      user: user,
      payment: payment
    } do
      Repo.delete!(user)
      payment = Repo.reload!(payment)

      assert {:ok, _} =
               Finance.refund(admin, payment, 10_000, %{
                 "reason" => "x",
                 "plan_action" => "end_now"
               })

      assert_email_sent(fn email ->
        match?([{_name, address}] when address == user.email, email.to)
      end)
    end

    test "needs finance.refund", %{payment: payment} do
      finance_viewer =
        Keepsakes.Staff.create_role(staff_scope_fixture(), %{
          "name" => "Viewers",
          "permissions" => ["finance.view"]
        })
        |> elem(1)
        |> then(&staff_scope_fixture([&1.key]))

      assert_raise Forbidden, fn ->
        Finance.refund(finance_viewer, payment, 100, %{
          "reason" => "x",
          "plan_action" => "end_now"
        })
      end
    end
  end

  describe "CSV" do
    test "exports payments and refunds, audited", %{
      admin: admin,
      user: user,
      invoice: invoice,
      payment: payment
    } do
      {:ok, _} =
        Finance.refund(admin, payment, 10_000, %{
          "reason" => "Late, sorry",
          "plan_action" => "end_at_period_end"
        })

      [header | rows] = Finance.payments_csv(admin, nil, nil)
      assert header =~ "date,invoice,name,email"
      assert Enum.any?(rows, &(&1 =~ invoice.number and &1 =~ user.email and &1 =~ ",100.00,"))

      [_header, row] = Finance.refunds_csv(admin, nil, nil)
      assert row =~ "Late"
      assert row =~ "100.00"

      assert length(Audit.list(admin, %{"action" => "finance.exported"})) == 2
    end

    test "neutralises spreadsheet formulas and quotes commas", %{admin: admin, invoice: invoice} do
      Repo.update_all(from(i in Invoice, where: i.id == ^invoice.id),
        set: [billing_name: "=HYPERLINK(\"x\"), Inc"]
      )

      [_header | rows] = Finance.payments_csv(admin, nil, nil)
      assert Enum.any?(rows, &(&1 =~ ~s("'=HYPERLINK(""x""\), Inc")))
    end

    test "needs finance.export" do
      assert_raise Forbidden, fn ->
        Finance.payments_csv(staff_scope_fixture(["support"]), nil, nil)
      end
    end
  end
end
