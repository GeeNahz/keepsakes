defmodule Keepsakes.Metrics do
  @moduledoc """
  Numbers for the admin dashboard, computed live from the tables (no
  separate metrics store yet). Staff accounts are left out of every
  customer figure. Needs `dashboard.view`.

  Money stays per currency (NGN and USD are never added together), in
  minor units. MRR counts each paying subscription's list price (a yearly
  price counts a twelfth), before discounts.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.User
  alias Keepsakes.Albums.Memory
  alias Keepsakes.Billing.{Invoice, Plan, Subscription, SubscriptionEvent}
  alias Keepsakes.{Repo, Staff}
  alias Keepsakes.Staff.Scope, as: StaffScope
  alias Keepsakes.Support.Ticket

  @days 30

  @doc "Everything the dashboard shows, as one map."
  def dashboard(%StaffScope{} = scope, now \\ DateTime.utc_now()) do
    Staff.authorize!(scope, "dashboard.view")

    paying = paying_count()
    churned = churned_count(now)

    %{
      customers: customers_count(),
      new_7d: signups_since(DateTime.add(now, -7, :day)),
      new_30d: signups_since(DateTime.add(now, -@days, :day)),
      trials: trialing_count(),
      paying: paying,
      ever_paid: ever_paid_count(),
      churned_30d: churned,
      churn_rate: if(paying + churned > 0, do: churned / (paying + churned), else: nil),
      mrr: mrr(),
      storage_bytes:
        Repo.aggregate(
          from(m in Memory, where: m.user_id not in subquery(staff())),
          :sum,
          :stored_bytes
        ) || 0,
      open_tickets:
        Repo.aggregate(from(t in Ticket, where: t.status not in ["resolved", "closed"]), :count),
      signups_per_day: per_day(from(u in customers()), :inserted_at, now),
      uploads_per_day:
        per_day(from(m in Memory, where: m.user_id not in subquery(staff())), :inserted_at, now)
    }
  end

  defp staff, do: Staff.staff_user_ids_query()

  defp customers, do: from(u in User, where: u.id not in subquery(staff()))

  defp customers_count, do: Repo.aggregate(customers(), :count)

  defp signups_since(since),
    do: Repo.aggregate(from(u in customers(), where: u.inserted_at >= ^since), :count)

  defp customer_subscriptions do
    from s in Subscription,
      join: p in Plan,
      on: p.id == s.plan_id,
      as: :plan,
      where: s.user_id not in subquery(staff())
  end

  defp trialing_count,
    do: Repo.aggregate(from(s in customer_subscriptions(), where: s.status == "trialing"), :count)

  defp paying_query do
    from [s, plan: p] in customer_subscriptions(),
      where: p.kind == "paid" and s.status in ["active", "past_due"]
  end

  defp paying_count, do: Repo.aggregate(paying_query(), :count)

  defp ever_paid_count do
    from(i in Invoice,
      where: i.status == "paid" and i.amount_minor > 0 and i.user_id not in subquery(staff()),
      select: count(i.user_id, :distinct)
    )
    |> Repo.one()
  end

  # Moved from a paid plan to a non-paid one in the last 30 days
  defp churned_count(now) do
    paid_slugs = from(p in Plan, where: p.kind == "paid", select: p.slug)
    since = DateTime.add(now, -@days, :day)

    from(e in SubscriptionEvent,
      join: s in Subscription,
      on: s.id == e.subscription_id,
      where:
        e.inserted_at >= ^since and e.from_plan in subquery(paid_slugs) and
          e.to_plan not in subquery(paid_slugs) and s.user_id not in subquery(staff()),
      select: count(s.user_id, :distinct)
    )
    |> Repo.one()
  end

  @doc false
  # %{"NGN" => minor_per_month, ...}
  def mrr do
    from([s] in paying_query(),
      join: pr in assoc(s, :price),
      group_by: pr.currency,
      select:
        {pr.currency,
         sum(
           fragment(
             "CASE WHEN ? = 'year' THEN ? / 12.0 ELSE ? END",
             pr.interval,
             pr.amount_minor,
             pr.amount_minor
           )
         )}
    )
    |> Repo.all()
    |> Map.new(fn {currency, total} ->
      {currency, total |> Decimal.round(0) |> Decimal.to_integer()}
    end)
  end

  # [{date, count}] for each of the last 30 days, oldest first, zeros included
  defp per_day(query, field, now) do
    today = DateTime.to_date(now)
    first = Date.add(today, -(@days - 1))
    since = DateTime.new!(first, ~T[00:00:00], "Etc/UTC")

    counts =
      from(r in query,
        where: field(r, ^field) >= ^since,
        group_by: fragment("1"),
        # Timestamps are stored in UTC without a zone
        select: {fragment("?::date", field(r, ^field)), count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    for date <- Date.range(first, today), do: {date, Map.get(counts, date, 0)}
  end
end
