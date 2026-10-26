defmodule Keepsakes.Customers do
  @moduledoc """
  Customer accounts as staff see them in the admin portal: finding them,
  everything about one account in one place, and the fixes staff can make
  (extend a trial, gift free months, give a plan, move to Free, suspend).

  Every function takes the `%Keepsakes.Staff.Scope{}` and checks the
  permission itself: `users.view` to look, `users.manage` to change. Each
  change is written to the audit log (and to the subscription's events
  where it touches the plan) in the same transaction. Staff accounts are
  never listed or changed here.
  """
  import Ecto.Query

  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.Billing.{Notifier, Payments, Plan, Subscription, SubscriptionEvent}
  alias Keepsakes.{Albums, Audit, Billing, Entitlements, Repo, Staff, Support}
  alias Keepsakes.Staff.Scope, as: StaffScope

  @page_size 50

  @statuses [
    {"On the free trial", "trialing"},
    {"In grace", "grace"},
    {"Active", "active"},
    {"Payment due", "past_due"},
    {"Canceled", "canceled"},
    {"Suspended", "suspended"},
    {"Deletion pending", "deletion"}
  ]

  @doc "Status filter options, `[{label, value}]`."
  def statuses, do: @statuses

  @doc "Plan filter options, `[{name, slug}]`."
  def plan_options do
    Repo.all(from p in Plan, order_by: [asc: p.position], select: {p.name, p.slug})
  end

  ## Finding customers

  @doc """
  Customers, newest first, `#{@page_size}` per page (`page` from 0).
  Filters: `"q"` (name or email contains), `"plan"` (slug), `"status"`
  (see `statuses/0`). Returns `{rows, more?}`; each row is
  `%{id, user, subscription, albums, storage_bytes}`.
  """
  def list(%StaffScope{} = scope, filters \\ %{}, page \\ 0) do
    Staff.authorize!(scope, "users.view")

    albums = from(a in Album, group_by: a.user_id, select: %{user_id: a.user_id, n: count(a.id)})

    storage =
      from(m in Memory,
        group_by: m.user_id,
        select: %{user_id: m.user_id, bytes: sum(m.stored_bytes)}
      )

    rows =
      from(u in User,
        as: :user,
        where: u.id not in subquery(Staff.staff_user_ids_query()),
        left_join: s in Subscription,
        as: :subscription,
        on: s.user_id == u.id,
        left_join: p in Plan,
        as: :plan,
        on: p.id == s.plan_id,
        left_join: a in subquery(albums),
        on: a.user_id == u.id,
        left_join: m in subquery(storage),
        on: m.user_id == u.id,
        order_by: [desc: u.inserted_at, desc: u.id],
        offset: ^(page * @page_size),
        limit: ^(@page_size + 1),
        select: {u, s, p, coalesce(a.n, 0), coalesce(m.bytes, 0)}
      )
      |> search(filters["q"])
      |> by_plan(filters["plan"])
      |> by_status(filters["status"])
      |> Repo.all()
      |> Enum.map(fn {user, subscription, plan, albums, bytes} ->
        %{
          id: user.id,
          user: user,
          subscription: subscription && %{subscription | plan: plan},
          albums: albums,
          storage_bytes: to_integer(bytes)
        }
      end)

    {Enum.take(rows, @page_size), length(rows) > @page_size}
  end

  defp search(query, q) when q in [nil, ""], do: query

  defp search(query, q) do
    like = "%" <> String.replace(String.trim(q), ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [user: u],
      ilike(u.email, ^like) or ilike(u.first_name, ^like) or ilike(u.last_name, ^like) or
        ilike(fragment("? || ' ' || coalesce(?, '')", u.first_name, u.last_name), ^like)
    )
  end

  defp by_plan(query, slug) when slug in [nil, ""], do: query
  defp by_plan(query, slug), do: where(query, [plan: p], p.slug == ^slug)

  defp by_status(query, s) when s in [nil, ""], do: query
  defp by_status(query, "suspended"), do: where(query, [user: u], not is_nil(u.suspended_at))

  defp by_status(query, "deletion"),
    do: where(query, [user: u], not is_nil(u.deletion_requested_at))

  defp by_status(query, status), do: where(query, [subscription: s], s.status == ^status)

  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n), do: n

  ## One customer

  @doc "A customer by ID. Raises `Ecto.NoResultsError` for staff or unknown IDs."
  def get!(%StaffScope{} = scope, id) do
    Staff.authorize!(scope, "users.view")

    Repo.one!(
      from u in User,
        where: u.id == ^id and u.id not in subquery(Staff.staff_user_ids_query())
    )
  end

  @doc """
  Everything the profile page shows about `user`. Invoices are only
  included with `finance.view` (otherwise `nil`).
  """
  def profile(%StaffScope{} = scope, %User{} = user) do
    Staff.authorize!(scope, "users.view")
    owner = Scope.for_user(user)
    subscription = Billing.get_subscription_details(owner)
    albums = Albums.list_albums(owner)

    %{
      subscription: subscription,
      events: events(subscription),
      payment_method: Billing.payment_method(owner),
      limits: Entitlements.all(owner),
      storage_used: Albums.storage_used(owner),
      photos: Enum.sum(Enum.map(albums, & &1.memories_count)),
      albums: albums,
      shared_album_ids: shared_album_ids(user),
      tickets: Support.list_tickets(owner),
      invoices: if(StaffScope.can?(scope, "finance.view"), do: Payments.list_invoices(owner)),
      activity:
        if(StaffScope.can?(scope, "audit.view"),
          do: Audit.list(scope, %{"target_id" => user.id}, 50)
        )
    }
  end

  defp events(nil), do: []

  defp events(%Subscription{id: id}) do
    Repo.all(
      from e in SubscriptionEvent,
        where: e.subscription_id == ^id,
        order_by: [desc: e.inserted_at],
        limit: 50
    )
  end

  defp shared_album_ids(user) do
    from(l in Keepsakes.Sharing.ShareLink, where: l.user_id == ^user.id, select: l.album_id)
    |> Repo.all()
    |> MapSet.new()
  end

  ## Changes (users.manage)

  @max_trial_days 90
  @max_gift_months 12

  @doc """
  Adds `days` (1–#{@max_trial_days}) to the free trial. Works while
  trialing, or in grace after the trial (back to trialing from today).
  """
  def extend_trial(%StaffScope{} = scope, %User{} = user, days) do
    Staff.authorize!(scope, "users.manage")
    now = DateTime.utc_now(:second)
    subscription = subscription(user)

    cond do
      not is_integer(days) or days < 1 or days > @max_trial_days ->
        {:error, :invalid}

      not on_trial?(subscription) ->
        {:error, :not_on_trial}

      true ->
        from_end = latest(subscription.trial_ends_at, now)
        ends_at = DateTime.add(from_end, days, :day)

        change(scope, user, subscription, "trial_extended",
          changes: [
            status: "trialing",
            trial_ends_at: ends_at,
            trial_reminder_sent_at: nil,
            grace_ends_at: nil
          ],
          audit: %{
            "days" => days,
            "before" => iso(subscription.trial_ends_at),
            "after" => iso(ends_at)
          }
        )
        |> notify(fn -> Notifier.deliver_trial_extended(user, ends_at) end)
    end
  end

  @doc "Whether the trial can be extended (trialing, or in grace after it)."
  def on_trial?(%Subscription{status: "trialing"}), do: true
  def on_trial?(%Subscription{status: "grace", plan: %Plan{kind: "trial"}}), do: true
  def on_trial?(_subscription), do: false

  @doc """
  Banks `months` (1–#{@max_gift_months}) free months, spent on the
  customer's next paid checkout (the same as referral months). Needs a
  reason for the audit log.
  """
  def gift_months(%StaffScope{} = scope, %User{} = user, months, reason) do
    Staff.authorize!(scope, "users.manage")
    reason = String.trim(reason || "")

    cond do
      not is_integer(months) or months < 1 or months > @max_gift_months ->
        {:error, :invalid}

      reason == "" ->
        {:error, :reason_required}

      true ->
        Repo.transact(fn ->
          user = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
          after_months = user.free_months_banked + months

          user =
            user |> Ecto.Changeset.change(free_months_banked: after_months) |> Repo.update!()

          audit(scope, "customer.months_gifted", user, %{
            "months" => months,
            "before" => after_months - months,
            "after" => after_months,
            "reason" => reason
          })

          {:ok, user}
        end)
    end
  end

  @doc """
  Puts the customer on the paid plan `plan_slug` until the end of `until`
  (a date), free of charge. It then moves to Free like a cancelled plan.
  Not for someone paying for a plan now.
  """
  def give_plan(%StaffScope{} = scope, %User{} = user, plan_slug, %Date{} = until) do
    Staff.authorize!(scope, "users.manage")
    now = DateTime.utc_now(:second)
    subscription = subscription(user)
    plan = Repo.get_by(Plan, slug: plan_slug)
    ends_at = DateTime.new!(until, ~T[23:59:59], "Etc/UTC")

    cond do
      is_nil(plan) or plan.kind != "paid" ->
        {:error, :invalid}

      not DateTime.after?(ends_at, now) or Date.diff(until, Date.utc_today()) > 731 ->
        {:error, :invalid_date}

      paying?(subscription) ->
        {:error, :paying}

      true ->
        change(scope, user, subscription, "plan_given",
          to_plan: plan.slug,
          changes: [
            plan_id: plan.id,
            price_id: nil,
            pending_price_id: nil,
            status: "active",
            complimentary: true,
            cancel_at_period_end: true,
            current_period_start: now,
            current_period_end: ends_at,
            grace_ends_at: nil,
            retry_count: 0,
            next_retry_at: nil
          ],
          audit: %{
            "before" => subscription.plan.name,
            "after" => plan.name,
            "until" => Date.to_iso8601(until)
          }
        )
        |> notify(fn -> Notifier.deliver_plan_given(user, plan, ends_at) end)
    end
  end

  @doc "Paying for a plan right now (staff don't touch a live paid period)."
  def paying?(%Subscription{complimentary: true}), do: false

  def paying?(%Subscription{status: status, plan: %Plan{kind: "paid"}})
      when status in ["active", "past_due", "grace"],
      do: true

  def paying?(_subscription), do: false

  @doc "Paid plans that can be given, as `[{name, slug}]`."
  def giftable_plans do
    Repo.all(
      from p in Plan,
        where: p.kind == "paid",
        order_by: [asc: p.position],
        select: {p.name, p.slug}
    )
  end

  @doc "Moves a trialing customer, or one on a given plan, to Free now."
  def move_to_free(%StaffScope{} = scope, %User{} = user) do
    Staff.authorize!(scope, "users.manage")
    subscription = subscription(user)
    free = Repo.get_by!(Plan, slug: "free")

    cond do
      subscription.plan_id == free.id ->
        {:error, :already_free}

      paying?(subscription) ->
        {:error, :paying}

      true ->
        change(scope, user, subscription, "moved_to_free_by_staff",
          to_plan: "free",
          changes: [
            plan_id: free.id,
            price_id: nil,
            pending_price_id: nil,
            status: "active",
            complimentary: false,
            cancel_at_period_end: false,
            current_period_start: nil,
            current_period_end: nil,
            grace_ends_at: nil
          ],
          audit: %{"before" => subscription.plan.name, "after" => free.name}
        )
    end
  end

  @doc """
  Suspends the account with `reason`: no sign-in, shared links stop,
  renewals pause. Returns `{:ok, user, tokens}`; disconnect the tokens'
  live sessions (`KeepsakesWeb.UserAuth.disconnect_sessions/1`).
  """
  def suspend(%StaffScope{} = scope, %User{} = user, reason) do
    Staff.authorize!(scope, "users.manage")
    reason = String.trim(reason || "")

    cond do
      reason == "" ->
        {:error, :reason_required}

      user.suspended_at ->
        {:error, :already_suspended}

      Staff.staff?(user) ->
        {:error, :staff}

      true ->
        {:ok, user, tokens} = Accounts.suspend(user, reason)
        audit(scope, "customer.suspended", user, %{"reason" => reason})
        {:ok, user, tokens}
    end
  end

  @doc "Lifts a suspension."
  def unsuspend(%StaffScope{} = scope, %User{suspended_at: %DateTime{}} = user) do
    Staff.authorize!(scope, "users.manage")

    Repo.transact(fn ->
      {:ok, unsuspended} = Accounts.unsuspend(user)
      audit(scope, "customer.unsuspended", user, %{"reason was" => user.suspension_reason})
      {:ok, unsuspended}
    end)
  end

  def unsuspend(_scope, _user), do: {:error, :not_suspended}

  ## Helpers

  defp subscription(user) do
    Repo.one!(from s in Subscription, where: s.user_id == ^user.id, preload: :plan)
  end

  # Applies `changes` to the subscription, with its event and audit entry
  defp change(scope, user, subscription, kind, opts) do
    changes = Keyword.fetch!(opts, :changes)

    Repo.transact(fn ->
      updated = subscription |> Ecto.Changeset.change(changes) |> Repo.update!()

      Repo.insert!(%SubscriptionEvent{
        subscription_id: subscription.id,
        kind: kind,
        from_status: subscription.status,
        to_status: updated.status,
        from_plan: subscription.plan.slug,
        to_plan: Keyword.get(opts, :to_plan, subscription.plan.slug)
      })

      audit(scope, "customer." <> kind, user, Keyword.fetch!(opts, :audit))
      {:ok, Repo.preload(updated, :plan, force: true)}
    end)
    |> tap(fn
      {:ok, _} -> Billing.broadcast_change(user.id)
      _ -> :ok
    end)
  end

  defp notify({:ok, _} = result, deliver) do
    deliver.()
    result
  end

  defp notify(error, _deliver), do: error

  defp audit(scope, action, user, changes),
    do: Audit.record(scope, action, {"user", user.id, user.email}, changes)

  defp latest(nil, now), do: now
  defp latest(at, now), do: if(DateTime.after?(at, now), do: at, else: now)

  defp iso(nil), do: nil
  defp iso(at), do: DateTime.to_iso8601(at)
end
