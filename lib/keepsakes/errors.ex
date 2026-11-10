defmodule Keepsakes.Errors do
  @moduledoc """
  Application errors for the admin portal, read from ErrorTracker's tables
  (`ErrorTracker.Error`, one row per distinct error, and
  `ErrorTracker.Occurrence`, one per time it happened, with the stack trace
  and request context).

  ErrorTracker records them; these pages show them inside the admin layout
  instead of mounting ErrorTracker's own dashboard. Seeing needs
  `errors.view`; resolving and muting need `errors.manage` and are audited.
  """
  import Ecto.Query

  alias ErrorTracker.{Error, Occurrence}
  alias Keepsakes.{Audit, Repo, Staff}
  alias Keepsakes.Staff.Scope

  @statuses ~w(unresolved resolved all)

  @doc "Status filter values, for the list page."
  def statuses, do: @statuses

  @doc """
  Errors, most recent first, each with how many times it happened.
  Filters: `"status"` (`unresolved` (default), `resolved`, `all`) and
  `"search"` (in the message, kind or source).
  """
  def list(%Scope{} = scope, filters \\ %{}, limit \\ 100) do
    Staff.authorize!(scope, "errors.view")

    counts =
      from o in Occurrence, group_by: o.error_id, select: %{error_id: o.error_id, count: count()}

    Error
    |> filter_status(filters["status"] || "unresolved")
    |> filter_search(String.trim(filters["search"] || ""))
    |> join(:left, [e], c in subquery(counts), on: c.error_id == e.id)
    |> order_by([e], desc: e.last_occurrence_at)
    |> limit(^limit)
    |> select([e, c], {e, coalesce(c.count, 0)})
    |> Repo.all()
  end

  defp filter_status(query, "resolved"), do: where(query, [e], e.status == :resolved)
  defp filter_status(query, "all"), do: query
  defp filter_status(query, _), do: where(query, [e], e.status == :unresolved)

  defp filter_search(query, ""), do: query

  defp filter_search(query, term) do
    like = "%" <> String.replace(term, ~r/[\\%_]/, &("\\" <> &1)) <> "%"

    where(
      query,
      [e],
      ilike(e.reason, ^like) or ilike(e.kind, ^like) or ilike(e.source_function, ^like) or
        ilike(e.source_line, ^like)
    )
  end

  @doc "How many errors are unresolved, for the sidebar and dashboard."
  def unresolved_count(%Scope{} = scope) do
    Staff.authorize!(scope, "errors.view")
    Repo.aggregate(from(e in Error, where: e.status == :unresolved), :count)
  end

  @doc "One error, raising if it doesn't exist."
  def get!(%Scope{} = scope, id) do
    Staff.authorize!(scope, "errors.view")
    Repo.get!(Error, id)
  end

  @doc "Its occurrences, newest first (the newest `limit`), and the total."
  def occurrences(%Scope{} = scope, %Error{id: id}, limit \\ 20) do
    Staff.authorize!(scope, "errors.view")
    base = from o in Occurrence, where: o.error_id == ^id

    {Repo.all(from o in base, order_by: [desc: o.inserted_at], limit: ^limit),
     Repo.aggregate(base, :count)}
  end

  @doc "Marks an error resolved (it reopens itself if it happens again)."
  def resolve(%Scope{} = scope, %Error{status: :unresolved} = error),
    do: change(scope, error, &ErrorTracker.resolve/1, "error.resolved")

  def resolve(_scope, %Error{} = error), do: {:ok, error}

  @doc "Marks a resolved error unresolved again."
  def unresolve(%Scope{} = scope, %Error{status: :resolved} = error),
    do: change(scope, error, &ErrorTracker.unresolve/1, "error.reopened")

  def unresolve(_scope, %Error{} = error), do: {:ok, error}

  @doc "Mutes or unmutes an error (still recorded; just flagged as known noise)."
  def set_muted(%Scope{} = scope, %Error{} = error, true),
    do: change(scope, error, &ErrorTracker.mute/1, "error.muted")

  def set_muted(%Scope{} = scope, %Error{} = error, false),
    do: change(scope, error, &ErrorTracker.unmute/1, "error.unmuted")

  defp change(scope, error, fun, action) do
    Staff.authorize!(scope, "errors.manage")

    with {:ok, updated} <- fun.(error) do
      Audit.record(scope, action, {"error", to_string(error.id), title(error)})
      {:ok, updated}
    end
  end

  @doc "A one-line name for an error: its kind and the start of its message."
  def title(%Error{kind: kind, reason: reason}) do
    first_line = reason |> to_string() |> String.split("\n", parts: 2) |> hd()
    "(#{kind}) " <> String.slice(first_line, 0, 120)
  end
end
