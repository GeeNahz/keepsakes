defmodule Keepsakes.CustomersTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Accounts, Audit, Billing, Customers, FlutterwaveStub, Sharing}
  alias Keepsakes.Billing.Invoice
  alias Keepsakes.Staff.Forbidden

  @return "http://localhost:4000/app/billing/return"

  setup do
    %{admin: staff_scope_fixture()}
  end

  defp customer(attrs \\ %{}) do
    user = user_fixture(attrs)
    flush_emails()
    user
  end

  # Drops the emails sent so far (the fixture's confirmation and sign-in link)
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp pay(user, plan \\ "plus") do
    FlutterwaveStub.stub()
    scope = Accounts.Scope.for_user(user)
    price = Billing.get_price!(plan, "NGN", "month")
    {:ok, {:redirect, link}} = Billing.start_checkout(scope, price, @return)
    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)
    flush_emails()
    Billing.get_subscription(user.id)
  end

  describe "list/3" do
    test "finds customers by name or email and leaves staff out", %{admin: admin} do
      ada = customer(first_name: "Ada", last_name: "Obi")
      _bola = customer(first_name: "Bola")

      {rows, false} = Customers.list(admin)
      ids = Enum.map(rows, & &1.id)
      assert ada.id in ids
      refute admin.user.id in ids
      assert length(rows) == 2

      assert {[%{id: id}], _} = Customers.list(admin, %{"q" => "ada ob"})
      assert id == ada.id
      assert {[%{id: ^id}], _} = Customers.list(admin, %{"q" => String.upcase(ada.email)})
      assert {[], _} = Customers.list(admin, %{"q" => "%"})
    end

    test "filters by plan and status", %{admin: admin} do
      trial = customer()
      free = customer()
      put_on_plan(free, "free")
      suspended = customer()
      {:ok, _, _} = Customers.suspend(admin, suspended, "Spam")

      ids = fn filters -> admin |> Customers.list(filters) |> elem(0) |> Enum.map(& &1.id) end

      assert ids.(%{"plan" => "free"}) == [free.id]
      assert trial.id in ids.(%{"status" => "trialing"})
      refute free.id in ids.(%{"status" => "trialing"})
      assert ids.(%{"status" => "suspended"}) == [suspended.id]
    end

    test "counts albums and storage", %{admin: admin} do
      user = customer()
      scope = Accounts.Scope.for_user(user)
      album = album_fixture(scope)
      memory = memory_fixture(scope, album)

      Repo.update_all(from(m in Keepsakes.Albums.Memory, where: m.id == ^memory.id),
        set: [stored_bytes: 1_400_000]
      )

      {[row], _} = Customers.list(admin, %{"q" => user.email})
      assert row.albums == 1
      assert row.storage_bytes == 1_400_000
    end

    test "needs users.view" do
      assert_raise Forbidden, fn -> Customers.list(staff_scope_fixture(["finance"])) end
    end
  end

  describe "get!/2 and profile/2" do
    test "staff accounts aren't customers", %{admin: admin} do
      assert_raise Ecto.NoResultsError, fn -> Customers.get!(admin, admin.user.id) end
    end

    test "invoices only with finance.view", %{admin: admin} do
      user = customer()
      assert is_list(Customers.profile(admin, user).invoices)

      support = staff_scope_fixture(["support"])
      profile = Customers.profile(support, user)
      assert profile.invoices == nil
      assert profile.activity == nil
    end
  end

  describe "extend_trial/3" do
    test "adds days, resets the reminder and emails the customer", %{admin: admin} do
      user = customer()
      before = Billing.get_subscription(user.id).trial_ends_at
      update_subscription(user, trial_reminder_sent_at: DateTime.utc_now(:second))

      assert {:ok, sub} = Customers.extend_trial(admin, user, 14)
      assert DateTime.diff(sub.trial_ends_at, before, :day) == 14
      assert sub.trial_reminder_sent_at == nil
      assert_email_sent(subject: "Your Keepsake trial now runs until " <> date(sub.trial_ends_at))

      assert [%{action: "customer.trial_extended", changes: %{"days" => 14}}] =
               Audit.list(admin, %{"target_id" => user.id})
    end

    test "brings a trial in grace back, counting from today", %{admin: admin} do
      user = customer()
      now = DateTime.utc_now(:second)

      update_subscription(user,
        status: "grace",
        trial_ends_at: DateTime.add(now, -3, :day),
        grace_ends_at: DateTime.add(now, 4, :day)
      )

      assert {:ok, sub} = Customers.extend_trial(admin, user, 10)
      assert sub.status == "trialing"
      assert sub.grace_ends_at == nil
      assert DateTime.diff(sub.trial_ends_at, now, :day) in 9..10
    end

    test "only on the trial and within limits", %{admin: admin} do
      user = customer()
      assert {:error, :invalid} = Customers.extend_trial(admin, user, 0)
      assert {:error, :invalid} = Customers.extend_trial(admin, user, 91)

      put_on_plan(user, "free")
      assert {:error, :not_on_trial} = Customers.extend_trial(admin, user, 5)
    end

    test "needs users.manage", %{admin: _admin} do
      support = staff_scope_fixture(["support"])
      assert_raise Forbidden, fn -> Customers.extend_trial(support, customer(), 5) end
    end
  end

  describe "gift_months/4" do
    test "banks months with a reason", %{admin: admin} do
      user = customer()
      assert {:error, :reason_required} = Customers.gift_months(admin, user, 2, " ")
      assert {:ok, user} = Customers.gift_months(admin, user, 2, "Sorry for the outage")
      assert user.free_months_banked == 2

      assert [%{changes: %{"reason" => "Sorry for the outage", "after" => 2}}] =
               Audit.list(admin, %{"action" => "customer.months_gifted"})
    end
  end

  describe "give_plan/4" do
    test "gives a paid plan until a date, free of charge", %{admin: admin} do
      user = customer()
      until = Date.add(Date.utc_today(), 30)

      assert {:ok, sub} = Customers.give_plan(admin, user, "plus", until)
      assert sub.plan.slug == "plus"
      assert sub.complimentary
      assert sub.cancel_at_period_end
      assert DateTime.to_date(sub.current_period_end) == until
      assert_email_sent(subject: "You've been given Keepsake Plus")
      assert Billing.status_label(Billing.get_subscription(user.id)) =~ "Plus"

      # It can't be resumed into a renewal: there's no card or price
      assert {:error, :not_cancelled} = Billing.resume(Accounts.Scope.for_user(user))
    end

    test "ends on its date and moves to Free without a charge", %{admin: admin} do
      user = customer()
      {:ok, _} = Customers.give_plan(admin, user, "plus", Date.add(Date.utc_today(), 1))

      later = DateTime.add(DateTime.utc_now(:second), 3, :day)
      assert %{cancelled: 1, renewed: 0} = Billing.advance(later)

      sub = Billing.get_subscription(user.id)
      assert sub.plan.slug == "free"
      refute sub.complimentary
      refute Repo.exists?(from i in Invoice, where: i.user_id == ^user.id)
    end

    test "paying for a plan ends the gift", %{admin: admin} do
      user = customer()
      {:ok, _} = Customers.give_plan(admin, user, "plus", Date.add(Date.utc_today(), 30))
      sub = pay(user, "pro")
      assert sub.plan.slug == "pro"
      refute sub.complimentary
      refute sub.cancel_at_period_end
    end

    test "not for a paying customer, a free plan or a past date", %{admin: admin} do
      user = customer()

      assert {:error, :invalid} =
               Customers.give_plan(admin, user, "free", Date.add(Date.utc_today(), 5))

      assert {:error, :invalid_date} =
               Customers.give_plan(admin, user, "plus", Date.utc_today() |> Date.add(-1))

      pay(user)

      assert {:error, :paying} =
               Customers.give_plan(admin, user, "pro", Date.add(Date.utc_today(), 5))
    end
  end

  describe "move_to_free/2" do
    test "ends a trial now", %{admin: admin} do
      user = customer()
      assert {:ok, sub} = Customers.move_to_free(admin, user)
      assert sub.plan.slug == "free"
      assert sub.status == "active"
      assert {:error, :already_free} = Customers.move_to_free(admin, user)
    end

    test "not for paying customers", %{admin: admin} do
      user = customer()
      pay(user)
      assert {:error, :paying} = Customers.move_to_free(admin, user)
    end
  end

  describe "suspend/3" do
    test "signs them out, blocks sign-in and stops their links", %{admin: admin} do
      user = customer()
      scope = Accounts.Scope.for_user(user)
      album = album_fixture(scope)
      link = share_link_fixture(scope, album)
      token = Accounts.generate_user_session_token(user)

      assert {:ok, user, [_ | _]} = Customers.suspend(admin, user, "Abuse report KS-T-1001")
      assert user.suspended_at
      refute Accounts.get_user_by_session_token(token)
      refute Sharing.get_link_by_slug(link.slug)
      assert {:error, :already_suspended} = Customers.suspend(admin, user, "again")

      assert {:ok, user} = Customers.unsuspend(admin, user)
      refute user.suspended_at
      assert Sharing.get_link_by_slug(link.slug)

      actions = admin |> Audit.list(%{"target_id" => user.id}) |> Enum.map(& &1.action)
      assert actions == ["customer.unsuspended", "customer.suspended"]
    end

    test "pauses renewals", %{admin: admin} do
      user = customer()
      pay(user)
      {:ok, _, _} = Customers.suspend(admin, user, "Chargeback")

      update_subscription(user,
        current_period_end: DateTime.add(DateTime.utc_now(:second), -1, :hour)
      )

      assert %{renewed: 0} = Billing.advance()
    end

    test "needs a reason, and never for staff", %{admin: admin} do
      assert {:error, :reason_required} = Customers.suspend(admin, customer(), "")
      assert {:error, :staff} = Customers.suspend(admin, staff_fixture(["support"]), "No")
    end
  end

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")
end
