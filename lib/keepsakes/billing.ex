defmodule Keepsakes.Billing do
  @moduledoc """
  Plans, prices and each user's subscription.

  Every new account starts a trial on the `trial` plan (Pro features) for
  `Settings.trial_days`. `advance/1`, run hourly by
  `Keepsakes.Billing.LifecycleWorker`, moves subscriptions along:

    1. a reminder email a week before the trial ends
    2. trial over: `grace` for `Settings.grace_days`, still with full access
    3. grace over: the Free plan, `active`

  Nothing is ever deleted on the way down; `Keepsakes.Entitlements` simply
  stops new additions that would go over the Free limits. Every step is
  recorded in `subscription_events`. Payments arrive in Stage 5b.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Billing.{Notifier, Plan, Price, Subscription, SubscriptionEvent}
  alias Keepsakes.{Repo, Settings}

  @reminder_days 7

  ## Plans

  @doc "Plans shown on the pricing page (Free and paid), with active prices."
  @spec list_public_plans() :: [Plan.t()]
  def list_public_plans do
    prices = from p in Price, where: p.active, order_by: [p.currency, p.interval]

    from(p in Plan, where: p.public, order_by: p.position, preload: [prices: ^prices])
    |> Repo.all()
  end

  @doc "The plan with `slug`. Raises when missing."
  @spec get_plan!(String.t()) :: Plan.t()
  def get_plan!(slug), do: Repo.get_by!(Plan, slug: slug)

  @doc "The plan's price for `currency` and `interval`, or nil."
  def price(%Plan{prices: prices}, currency, interval) when is_list(prices),
    do: Enum.find(prices, &(&1.currency == currency and &1.interval == interval))

  ## Subscriptions

  @doc "The user's subscription with its plan, or nil (treated as Free)."
  @spec get_subscription(Scope.t() | Ecto.UUID.t()) :: Subscription.t() | nil
  def get_subscription(%Scope{user: user}), do: get_subscription(user.id)

  def get_subscription(user_id) when is_binary(user_id) do
    Repo.one(from s in Subscription, where: s.user_id == ^user_id, preload: :plan)
  end

  @doc """
  The plan whose features apply right now: the subscription's plan, or Free
  when the user somehow has none.
  """
  @spec current_plan(Scope.t() | Ecto.UUID.t()) :: Plan.t()
  def current_plan(scope_or_user_id) do
    case get_subscription(scope_or_user_id) do
      %Subscription{plan: plan} -> plan
      nil -> get_plan!("free")
    end
  end

  @doc """
  Adds the trial subscription for the user inserted by the `user_step`
  of `multi` (used by registration, so both happen in one transaction).
  """
  @spec start_trial(Multi.t(), atom(), DateTime.t()) :: Multi.t()
  def start_trial(multi, user_step, now \\ DateTime.utc_now(:second)) do
    multi
    |> Multi.insert(:subscription, fn %{^user_step => %User{} = user} ->
      %Subscription{
        user_id: user.id,
        plan_id: get_plan!("trial").id,
        status: "trialing",
        trial_ends_at: DateTime.add(now, Settings.get(:trial_days), :day)
      }
    end)
    |> Multi.insert(:subscription_event, fn %{subscription: subscription} ->
      %SubscriptionEvent{
        subscription_id: subscription.id,
        kind: "trial_started",
        to_status: "trialing",
        to_plan: "trial"
      }
    end)
  end

  @doc """
  One line about where the subscription stands, e.g. `"Free trial · 12
  days left"` or `"Free plan"`.
  """
  @spec status_label(Subscription.t() | nil, DateTime.t()) :: String.t()
  def status_label(subscription, now \\ DateTime.utc_now())
  def status_label(nil, _now), do: "Free plan"

  def status_label(%Subscription{status: "grace"} = subscription, now),
    do: "Trial ended · " <> String.downcase(status_detail(subscription, now))

  def status_label(%Subscription{plan: plan} = subscription, now) do
    case status_detail(subscription, now) do
      nil -> "#{plan.name} plan"
      detail -> "#{plan.name} · #{String.downcase(detail)}"
    end
  end

  @doc """
  What's notable about the subscription's status, without the plan name:
  `"60 days left"`, `"Full access for 5 more days"`, `"Payment due"`, or
  nil when it's simply active.
  """
  @spec status_detail(Subscription.t() | nil, DateTime.t()) :: String.t() | nil
  def status_detail(subscription, now \\ DateTime.utc_now())

  def status_detail(%Subscription{status: "trialing", trial_ends_at: ends_at}, now),
    do: "#{days(ends_at, now)} left"

  def status_detail(%Subscription{status: "grace", grace_ends_at: ends_at}, now),
    do: "Full access for #{days(ends_at, now)} more"

  def status_detail(%Subscription{status: "past_due"}, _now), do: "Payment due"
  def status_detail(%Subscription{status: "canceled"}, _now), do: "Canceled"
  def status_detail(_subscription, _now), do: nil

  defp days(at, now) do
    case days_until(at, now) do
      1 -> "1 day"
      days -> "#{days} days"
    end
  end

  @doc "Whole days left until `at` (0 when past), for \"12 days left\"."
  def days_until(%DateTime{} = at, now \\ DateTime.utc_now()),
    do: max(0, ceil(DateTime.diff(at, now) / 86_400))

  ## Lifecycle

  @doc """
  Moves every due subscription one step along (see the module doc) and
  sends its email. Safe to run often: each step only matches
  subscriptions that haven't had it yet. Returns how many of each it did.
  """
  @spec advance(DateTime.t()) :: %{reminders: integer(), grace: integer(), free: integer()}
  def advance(now \\ DateTime.utc_now(:second)) do
    %{
      reminders: send_trial_reminders(now),
      grace: start_grace(now),
      free: move_to_free(now)
    }
  end

  defp send_trial_reminders(now) do
    remind_before = DateTime.add(now, @reminder_days, :day)

    from(s in Subscription,
      where:
        s.status == "trialing" and is_nil(s.trial_reminder_sent_at) and
          s.trial_ends_at <= ^remind_before and s.trial_ends_at > ^now,
      preload: [:user, :plan]
    )
    |> Repo.all()
    |> Enum.count(fn subscription ->
      step(
        subscription,
        "trial_reminder",
        dynamic([s], is_nil(s.trial_reminder_sent_at)),
        %{trial_reminder_sent_at: now},
        &Notifier.deliver_trial_ending(&1.user, &1.trial_ends_at)
      )
    end)
  end

  defp start_grace(now) do
    grace_ends_at = DateTime.add(now, Settings.get(:grace_days), :day)

    from(s in Subscription,
      where: s.status == "trialing" and s.trial_ends_at <= ^now,
      preload: [:user, :plan]
    )
    |> Repo.all()
    |> Enum.count(fn subscription ->
      step(
        subscription,
        "grace_started",
        true,
        %{status: "grace", grace_ends_at: grace_ends_at},
        &Notifier.deliver_grace_started(&1.user, &1.grace_ends_at)
      )
    end)
  end

  defp move_to_free(now) do
    free = get_plan!("free")

    from(s in Subscription,
      where: s.status == "grace" and s.grace_ends_at <= ^now,
      preload: [:user, :plan]
    )
    |> Repo.all()
    |> Enum.count(fn subscription ->
      changes = %{
        status: "active",
        plan_id: free.id,
        price_id: nil,
        grace_ends_at: nil,
        current_period_start: nil,
        current_period_end: nil
      }

      step(subscription, "moved_to_free", true, changes, &Notifier.deliver_moved_to_free(&1.user))
    end)
  end

  # Applies `changes` and records the event in one transaction, then emails.
  # The update only matches while the row still has the status we read (and
  # `guard`), so two runs at once never step, or email, twice.
  defp step(%Subscription{} = subscription, kind, guard, changes, notify) do
    %{id: id, status: status} = subscription

    Multi.new()
    |> Multi.update_all(
      :subscription,
      from(s in Subscription,
        where: s.id == ^id and s.status == ^status,
        where: ^guard,
        select: s
      ),
      set: Map.to_list(Map.put(changes, :updated_at, DateTime.utc_now(:second)))
    )
    |> Multi.run(:event, fn repo, %{subscription: {count, rows}} ->
      case {count, rows} do
        {1, [updated]} ->
          updated = repo.preload(updated, [:user, :plan], force: true)

          repo.insert(%SubscriptionEvent{
            subscription_id: id,
            kind: kind,
            from_status: status,
            to_status: updated.status,
            from_plan: subscription.plan.slug,
            to_plan: updated.plan.slug
          })
          |> case do
            {:ok, _} -> {:ok, updated}
            error -> error
          end

        _ ->
          {:error, :already_moved}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: updated}} ->
        notify.(updated)
        true

      {:error, _step, _reason, _} ->
        false
    end
  end
end
