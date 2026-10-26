defmodule Keepsakes.BillingFixtures do
  @moduledoc "Plans and subscription states for tests."
  import Ecto.Query

  alias Keepsakes.Billing
  alias Keepsakes.Billing.{Plan, Subscription}
  alias Keepsakes.Repo

  @doc "A plan whose features are the Free plan's, overridden by `features`."
  def plan_fixture(features \\ %{}, attrs \\ %{}) do
    %Plan{}
    |> Plan.changeset(
      Enum.into(attrs, %{
        slug: "test-#{System.unique_integer([:positive])}",
        name: "Test plan",
        kind: "paid",
        public: false,
        features: Map.merge(Billing.get_plan!("free").features, features)
      })
    )
    |> Repo.insert!()
  end

  @doc "Puts the user on `plan` (a slug or `%Plan{}`) as an active subscription."
  def put_on_plan(%{id: user_id}, plan) do
    plan = if is_binary(plan), do: Billing.get_plan!(plan), else: plan

    {1, _} =
      from(s in Subscription, where: s.user_id == ^user_id)
      |> Repo.update_all(set: [plan_id: plan.id, status: "active", trial_ends_at: nil])

    plan
  end

  @doc """
  Pays for `price` (or the NGN monthly price of the plan slug) through the
  stubbed gateway (`Keepsakes.FlutterwaveStub.stub/1` first). Returns the
  paid invoice with its payments.
  """
  def pay_fixture(user, price \\ "plus") do
    price = if is_binary(price), do: Billing.get_price!(price, "NGN", "month"), else: price
    scope = Keepsakes.Accounts.Scope.for_user(user)

    {:ok, {:redirect, link}} =
      Billing.start_checkout(scope, price, "http://localhost:4000/app/billing/return")

    "https://checkout.flutterwave.test/pay/" <> tx_ref = link
    {:ok, :paid} = Billing.confirm(tx_ref, "fw-" <> tx_ref)

    Repo.one!(
      from i in Keepsakes.Billing.Invoice,
        where: i.user_id == ^user.id and i.status == "paid",
        order_by: [desc: i.number],
        limit: 1,
        preload: :payments
    )
  end

  @doc "Sets subscription fields directly (e.g. to move a trial's end date)."
  def update_subscription(%{id: user_id}, fields) do
    {1, _} =
      from(s in Subscription, where: s.user_id == ^user_id)
      |> Repo.update_all(set: Enum.to_list(fields))

    Billing.get_subscription(user_id)
  end
end
