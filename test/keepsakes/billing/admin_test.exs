defmodule Keepsakes.Billing.AdminTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Billing, Entitlements, FlutterwaveStub}
  alias Keepsakes.Billing.{Admin, Payments, Plan, Price}
  alias Keepsakes.Staff.Forbidden

  setup do
    FlutterwaveStub.stub()
    %{admin: staff_scope_fixture()}
  end

  # The plan's current form params with `changes` merged in (nested maps too,
  # like the browser sending every field)
  defp form(plan, changes) do
    plan
    |> Admin.plan_params()
    |> Map.merge(changes, fn
      _key, old, new when is_map(old) and is_map(new) -> Map.merge(old, new)
      _key, _old, new -> new
    end)
  end

  defp plan(slug),
    do: Repo.get_by!(Plan, slug: slug) |> Repo.preload(prices: from(p in Price, where: p.active))

  describe "plans" do
    test "lists plans with how many accounts are on each", %{admin: admin} do
      user_fixture()
      counts = admin |> Admin.list_plans() |> Map.new(fn {p, n} -> {p.slug, n} end)
      assert counts["trial"] >= 1
      assert Map.keys(counts) |> Enum.sort() == ~w(free plus pro trial)
    end

    test "creates a hidden paid plan with features and prices", %{admin: admin} do
      params =
        form(Admin.new_plan(), %{
          "name" => "Family",
          "slug" => "family",
          "position" => "4",
          "public" => "false",
          "prices" => %{"NGN_month" => "7500", "USD_year" => "99.50"}
        })
        |> put_in(["features", "storage_bytes"], %{"value" => "50", "unlimited" => "false"})
        |> put_in(["features", "max_albums"], %{"value" => "", "unlimited" => "true"})
        |> put_in(["features", "premium_templates"], %{"value" => "true"})

      assert {:ok, plan} = Admin.create_plan(admin, params)
      assert plan.kind == "paid"
      refute plan.public
      assert plan.features["storage_bytes"] == 50 * 1024 * 1024 * 1024
      assert plan.features["max_albums"] == nil
      assert plan.features["premium_templates"] == true

      amounts = Map.new(plan.prices, &{{&1.currency, &1.interval}, &1.amount_minor})
      assert amounts == %{{"NGN", "month"} => 750_000, {"USD", "year"} => 9950}
      refute Enum.any?(Billing.list_public_plans(), &(&1.id == plan.id))

      assert [%{action: "plan.created"}] = Audit.list(admin, %{"action" => "plan."})
    end

    test "rejects bad prices and features", %{admin: admin} do
      params = form(plan("plus"), %{"prices" => %{"NGN_month" => "abc"}})
      assert {:error, changeset} = Admin.update_plan(admin, plan("plus"), params)
      assert errors_on(changeset)[:prices]

      params = form(plan("plus"), %{}) |> put_in(["features", "max_albums"], %{"value" => "-3"})
      assert {:error, changeset} = Admin.update_plan(admin, plan("plus"), params)
      assert errors_on(changeset)[:features]
    end

    test "feature changes apply to everyone on the plan", %{admin: admin} do
      user = user_fixture()
      put_on_plan(user, "free")
      before = Entitlements.limit(user.id, :max_albums)

      params = form(plan("free"), %{}) |> put_in(["features", "max_albums"], %{"value" => "7"})
      assert {:ok, _} = Admin.update_plan(admin, plan("free"), params)
      assert Entitlements.limit(user.id, :max_albums) == 7
      refute before == 7
    end

    test "Free and Trial plans only take name, description and features", %{admin: admin} do
      params = form(plan("free"), %{"public" => "false", "position" => "9", "name" => "Basic"})
      assert {:ok, free} = Admin.update_plan(admin, plan("free"), params)
      assert free.name == "Basic"
      assert free.public
      assert free.position == 1
    end

    test "needs plans.manage" do
      assert_raise Forbidden, fn -> Admin.list_plans(staff_scope_fixture(["finance"])) end
    end
  end

  describe "price changes" do
    test "new buyers get the new price; subscribers keep paying the old one", %{admin: admin} do
      old = Billing.get_price!("plus", "NGN", "month")
      subscriber = user_fixture()
      pay_fixture(subscriber)

      params = form(plan("plus"), %{"prices" => %{"NGN_month" => "9000"}})
      assert {:ok, _} = Admin.update_plan(admin, plan("plus"), params)

      new = Billing.get_price!("plus", "NGN", "month")
      assert new.amount_minor == 900_000
      refute Repo.reload!(old).active

      # The renewal charges the subscriber's own (old) price
      update_subscription(subscriber,
        current_period_end: DateTime.add(DateTime.utc_now(:second), -1, :hour)
      )

      assert %{renewed: 1} = Billing.advance()

      renewal =
        Repo.one!(
          from i in Keepsakes.Billing.Invoice,
            where: i.user_id == ^subscriber.id and i.kind == "renewal"
        )

      assert renewal.amount_minor == old.amount_minor

      assert [%{changes: %{"price" => "NGN_month", "before" => before, "after" => 900_000}}] =
               Audit.list(admin, %{"action" => "price.changed"})

      assert before == old.amount_minor
    end

    test "someone in grace can still pay their old price", %{admin: admin} do
      old = Billing.get_price!("plus", "NGN", "month")
      user = user_fixture()
      pay_fixture(user)

      {:ok, _} =
        Admin.update_plan(
          admin,
          plan("plus"),
          form(plan("plus"), %{"prices" => %{"NGN_month" => "9000"}})
        )

      update_subscription(user, status: "grace")
      scope = Keepsakes.Accounts.Scope.for_user(user)
      assert {:ok, %{price: %{id: id}}} = Payments.quote_price(scope, Repo.reload!(old))
      assert id == old.id

      # ...but a new buyer can't pick the old price
      other = Keepsakes.Accounts.Scope.for_user(user_fixture())
      assert {:error, :not_paid_plan} = Payments.quote_price(other, Repo.reload!(old))
    end

    test "emptying a price stops offering it", %{admin: admin} do
      params = form(plan("plus"), %{"prices" => %{"USD_year" => ""}})
      {:ok, plus} = Admin.update_plan(admin, plan("plus"), params)
      refute Enum.any?(plus.prices, &(&1.currency == "USD" and &1.interval == "year"))
    end
  end

  describe "discount codes" do
    test "creates a code with an end date and plans", %{admin: admin} do
      assert {:ok, code} =
               Admin.create_code(admin, %{
                 "code" => "spring",
                 "percent_off" => "15",
                 "duration" => "repeating",
                 "duration_months" => "3",
                 "max_redemptions" => "",
                 "expires_at" => "2027-03-31",
                 "plan_slugs" => ["", "plus"],
                 "active" => "true"
               })

      assert code.code == "SPRING"
      assert code.plan_slugs == ["plus"]
      assert code.max_redemptions == nil
      assert code.expires_at == ~U[2027-03-31 23:59:59Z]
      assert [%{action: "discount.created"}] = Audit.list(admin, %{"action" => "discount."})
    end

    test "what a used code gives is locked; its limits aren't", %{admin: admin} do
      {:ok, code} =
        Admin.create_code(admin, %{"code" => "TEN", "percent_off" => "10", "duration" => "once"})

      code = code |> Ecto.Changeset.change(redemptions_count: 1) |> Repo.update!()
      assert Admin.locked?(code)

      {:ok, code} =
        Admin.update_code(admin, code, %{
          "percent_off" => "90",
          "max_redemptions" => "5",
          "active" => "false"
        })

      assert code.percent_off == 10
      assert code.max_redemptions == 5
      refute code.active
    end

    test "totals what each code took off paid invoices", %{admin: admin} do
      {:ok, _} =
        Admin.create_code(admin, %{"code" => "HALF", "percent_off" => "50", "duration" => "once"})

      user = user_fixture()
      scope = Keepsakes.Accounts.Scope.for_user(user)
      price = Billing.get_price!("plus", "NGN", "month")

      {:ok, {:redirect, link}} =
        Billing.start_checkout(scope, price, "http://x/return", code: "half")

      "https://checkout.flutterwave.test/pay/" <> tx_ref = link
      {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)

      [{_code, discounted}] = Admin.list_codes(admin)

      assert discounted == %{
               "NGN" => Keepsakes.Billing.Discounts.amount_off(price.amount_minor, 50)
             }
    end

    test "need discounts.manage" do
      assert_raise Forbidden, fn -> Admin.list_codes(staff_scope_fixture(["support"])) end
    end
  end
end
