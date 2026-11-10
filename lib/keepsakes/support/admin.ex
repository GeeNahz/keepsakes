defmodule Keepsakes.Support.Admin do
  @moduledoc """
  The staff side of support, for the admin portal's inbox: finding
  tickets, the full thread (internal notes included), replying, notes,
  assignment, priority and status, the first-reply targets (SLA) and
  canned replies.

  Permissions: `support.view` to read, `support.reply` to answer, change
  status and manage canned replies, `support.assign` for assignee and
  priority. Every change is audited (message bodies aren't copied into
  the log) and broadcast so open pages update.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.User
  alias Keepsakes.Support.{CannedReply, Message, Ticket}
  alias Keepsakes.{Audit, Repo, Settings, Staff, Support}
  alias Keepsakes.Staff.{Membership, Scope}

  @page_size 50

  ## First-reply targets

  @doc "Hours to the first staff reply for a priority (system settings)."
  def sla_hours("urgent"), do: Settings.get(:sla_urgent_hours)
  def sla_hours("high"), do: Settings.get(:sla_high_hours)
  def sla_hours("low"), do: Settings.get(:sla_low_hours)
  def sla_hours(_normal), do: Settings.get(:sla_normal_hours)

  @doc "When the first staff reply is due."
  def due_at(%Ticket{inserted_at: at, priority: priority}),
    do: DateTime.add(at, sla_hours(priority), :hour)

  @doc """
  Where a ticket stands against its first-reply target: `:replied`,
  `:overdue`, `:due_soon` (under a quarter of the window, or an hour, left),
  `:on_track`, or `:none` (closed without needing a reply).
  """
  def sla(%Ticket{} = ticket, now \\ DateTime.utc_now()) do
    cond do
      ticket.first_response_at -> :replied
      ticket.status in ["resolved", "closed"] -> :none
      true -> sla_state(ticket, now)
    end
  end

  defp sla_state(ticket, now) do
    due = due_at(ticket)
    left = DateTime.diff(due, now)
    window = sla_hours(ticket.priority) * 3600

    cond do
      left <= 0 -> :overdue
      left < max(div(window, 4), 0) or left < 3600 -> :due_soon
      true -> :on_track
    end
  end

  ## Inbox

  @doc """
  Tickets for the inbox, `#{@page_size}` per page. Filters: `"view"`
  (`"needs_reply"`, the default: new or waiting on staff; or `"all"`),
  `"status"`, `"priority"`, `"category"`, `"assignee"` (`"me"`,
  `"unassigned"`) and `"q"` (number, subject or email). Unanswered tickets
  come first by when their reply is due, then the most recently active.
  Returns `{tickets, more?}`.
  """
  def list(%Scope{} = scope, filters \\ %{}, page \\ 0) do
    Staff.authorize!(scope, "support.view")

    hours =
      Map.new(~w(urgent high normal low), &{&1, sla_hours(&1)})

    tickets =
      from(t in Ticket,
        as: :ticket,
        left_join: u in assoc(t, :user),
        as: :user,
        preload: [user: u, assignee: []],
        order_by: [
          asc_nulls_last:
            fragment(
              "CASE WHEN ? IS NULL AND ? NOT IN ('resolved', 'closed') THEN ? + make_interval(hours => CASE ? WHEN 'urgent' THEN ?::integer WHEN 'high' THEN ?::integer WHEN 'low' THEN ?::integer ELSE ?::integer END) END",
              t.first_response_at,
              t.status,
              t.inserted_at,
              t.priority,
              ^hours["urgent"],
              ^hours["high"],
              ^hours["low"],
              ^hours["normal"]
            ),
          desc: t.last_activity_at,
          desc: t.id
        ],
        offset: ^(page * @page_size),
        limit: ^(@page_size + 1)
      )
      |> filter(:view, filters["view"] || "needs_reply")
      |> filter(:status, filters["status"])
      |> filter(:priority, filters["priority"])
      |> filter(:category, filters["category"])
      |> filter(:assignee, {filters["assignee"], scope.user.id})
      |> filter(:q, filters["q"])
      |> Repo.all()

    {Enum.take(tickets, @page_size), length(tickets) > @page_size}
  end

  defp filter(query, _key, value) when value in [nil, ""], do: query
  defp filter(query, :view, "all"), do: query

  defp filter(query, :view, _needs_reply),
    do: where(query, [ticket: t], t.status in ["open", "awaiting_staff"])

  defp filter(query, :status, s), do: where(query, [ticket: t], t.status == ^s)
  defp filter(query, :priority, p), do: where(query, [ticket: t], t.priority == ^p)
  defp filter(query, :category, c), do: where(query, [ticket: t], t.category == ^c)
  defp filter(query, :assignee, {"me", me}), do: where(query, [ticket: t], t.assignee_id == ^me)

  defp filter(query, :assignee, {"unassigned", _}),
    do: where(query, [ticket: t], is_nil(t.assignee_id))

  defp filter(query, :assignee, _), do: query

  defp filter(query, :q, q) do
    like = "%" <> String.replace(String.trim(q), ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [ticket: t, user: u],
      ilike(t.number, ^like) or ilike(t.subject, ^like) or ilike(u.email, ^like) or
        ilike(t.reporter_email, ^like)
    )
  end

  @doc "How many tickets need a reply (for the sidebar)."
  def needs_reply_count do
    Repo.aggregate(from(t in Ticket, where: t.status in ["open", "awaiting_staff"]), :count)
  end

  ## One ticket

  @doc "The ticket with every message (internal notes too), people and the reported album."
  def get!(%Scope{} = scope, number) do
    Staff.authorize!(scope, "support.view")

    messages =
      from m in Message,
        order_by: [asc: m.inserted_at, asc: m.id],
        preload: [:attachments, :author]

    Repo.one!(
      from t in Ticket,
        where: t.number == ^number,
        preload: [:user, :assignee, :album, :share_link, messages: ^messages]
    )
  end

  @doc "Staff who can be assigned tickets (they can open the inbox)."
  def assignable_staff do
    from(m in Membership,
      join: u in assoc(m, :user),
      where: m.active,
      preload: [:roles, user: u],
      order_by: u.first_name
    )
    |> Repo.all()
    |> Enum.filter(fn m ->
      Enum.any?(m.roles, &(&1.system or "support.view" in &1.permissions))
    end)
    |> Enum.map(& &1.user)
  end

  ## Changes

  @doc """
  Answers the customer (`internal: false`) or adds a note only staff see
  (`internal: true`). Replies set the ticket to waiting on the customer,
  record the first response and email them (`Support.staff_reply/4`).
  """
  def reply(%Scope{} = scope, %Ticket{} = ticket, body, internal? \\ false) do
    Staff.authorize!(scope, "support.reply")
    body = String.trim(body || "")

    cond do
      body == "" ->
        {:error, :empty}

      ticket.status == "closed" and not internal? ->
        {:error, :closed}

      true ->
        {:ok, message} = Support.staff_reply(ticket, scope.user, body, internal: internal?)
        audit(scope, if(internal?, do: "ticket.noted", else: "ticket.replied"), ticket, %{})
        {:ok, message}
    end
  end

  @doc "Assigns the ticket to a staff member (or nobody, with nil)."
  def assign(%Scope{} = scope, %Ticket{} = ticket, assignee_id) do
    Staff.authorize!(scope, "support.assign")
    assignee_id = if assignee_id in [nil, ""], do: nil, else: assignee_id

    allowed? = is_nil(assignee_id) or Enum.any?(assignable_staff(), &(&1.id == assignee_id))

    if allowed? do
      before = ticket.assignee_id && Repo.get(User, ticket.assignee_id)
      assignee = assignee_id && Repo.get(User, assignee_id)

      update(scope, ticket, [assignee_id: assignee_id], "ticket.assigned", %{
        "before" => before && before.email,
        "after" => assignee && assignee.email
      })
    else
      {:error, :not_staff}
    end
  end

  @priorities ~w(low normal high urgent)

  @doc "Priorities, lowest first."
  def priorities, do: @priorities

  @doc "Changes the priority (and so the first-reply target)."
  def set_priority(%Scope{} = scope, %Ticket{} = ticket, priority) when priority in @priorities do
    Staff.authorize!(scope, "support.assign")

    update(scope, ticket, [priority: priority], "ticket.priority", %{
      "before" => ticket.priority,
      "after" => priority
    })
  end

  def set_priority(_scope, _ticket, _priority), do: {:error, :invalid}

  @doc "Staff mark it solved (`\"resolved\"`), reopen it (`\"awaiting_staff\"`) or close it."
  def set_status(%Scope{} = scope, %Ticket{} = ticket, status) do
    Staff.authorize!(scope, "support.reply")
    now = DateTime.utc_now(:second)

    result =
      case {ticket.status, status} do
        {from, "resolved"} when from not in ["resolved", "closed"] ->
          Support.set_status(ticket, "resolved", "Marked as solved by support", resolved_at: now)

        {from, "awaiting_staff"} when from in ["resolved", "closed"] ->
          Support.set_status(ticket, "awaiting_staff", "Reopened by support",
            resolved_at: nil,
            closed_at: nil
          )

        {from, "closed"} when from != "closed" ->
          Support.set_status(ticket, "closed", "Closed by support", closed_at: now)

        _ ->
          {:error, :invalid}
      end

    with {:ok, updated} <- result do
      audit(scope, "ticket.status", ticket, %{
        "before" => ticket.status,
        "after" => updated.status
      })

      {:ok, updated}
    end
  end

  defp update(scope, ticket, changes, action, audit_changes) do
    Repo.transact(fn ->
      updated = ticket |> Ecto.Changeset.change(changes) |> Repo.update!()
      audit(scope, action, ticket, audit_changes)
      {:ok, updated}
    end)
    |> tap(fn
      {:ok, updated} -> Support.broadcast(updated)
      _ -> :ok
    end)
  end

  defp audit(scope, action, ticket, changes),
    do: Audit.record(scope, action, {"ticket", ticket.id, ticket.number}, changes)

  ## Canned replies

  def list_replies(%Scope{} = scope) do
    Staff.authorize!(scope, "support.view")
    Repo.all(from r in CannedReply, order_by: r.title)
  end

  def get_reply!(%Scope{} = scope, id) do
    Staff.authorize!(scope, "support.view")
    Repo.get!(CannedReply, id)
  end

  def change_reply(%CannedReply{} = reply, attrs \\ %{}), do: CannedReply.changeset(reply, attrs)

  def save_reply(%Scope{} = scope, %CannedReply{} = reply, attrs) do
    Staff.authorize!(scope, "support.reply")
    action = if reply.id, do: "canned_reply.updated", else: "canned_reply.created"

    Repo.transact(fn ->
      with {:ok, saved} <- reply |> CannedReply.changeset(attrs) |> Repo.insert_or_update() do
        Audit.record(scope, action, {"canned_reply", saved.id, saved.title})
        {:ok, saved}
      end
    end)
  end

  def delete_reply(%Scope{} = scope, %CannedReply{} = reply) do
    Staff.authorize!(scope, "support.reply")

    Repo.transact(fn ->
      {:ok, deleted} = Repo.delete(reply)
      Audit.record(scope, "canned_reply.deleted", {"canned_reply", reply.id, reply.title})
      {:ok, deleted}
    end)
  end
end
