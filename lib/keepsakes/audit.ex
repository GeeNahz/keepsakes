defmodule Keepsakes.Audit do
  @moduledoc """
  The admin audit log: every change made through the admin portal records
  who did it, what, to which record, the before/after values and the IP.
  Admin context functions call `record/4` in the same transaction as the
  change, so a change and its record stand or fall together.
  """
  import Ecto.Query

  alias Keepsakes.Audit.Event
  alias Keepsakes.Repo
  alias Keepsakes.Staff.Scope, as: StaffScope

  @doc """
  Records `action` by the staff member in `scope` (or `:system`) on
  `target` (`{type, id, label}` or nil) with `changes` (e.g.
  `%{"before" => ..., "after" => ...}`).
  """
  @spec record(
          StaffScope.t() | :system,
          String.t(),
          {String.t(), term(), String.t()} | nil,
          map()
        ) ::
          Event.t()
  def record(actor, action, target, changes \\ %{}) do
    {type, id, label} = target || {nil, nil, nil}

    {actor_id, actor_email, ip} =
      case actor do
        %StaffScope{user: user, ip: ip} -> {user.id, user.email, ip}
        :system -> {nil, "system", nil}
      end

    Repo.insert!(%Event{
      actor_id: actor_id,
      actor_email: actor_email,
      action: action,
      target_type: type,
      target_id: id && to_string(id),
      target_label: label,
      changes: changes,
      ip: ip
    })
  end

  @doc """
  Recent events, newest first (needs `audit.view`). Filters: `"action"` (prefix, e.g. `"staff"`),
  `"actor"` (email contains), `"target_id"`; at most `limit` rows.
  """
  def list(%StaffScope{} = scope, filters \\ %{}, limit \\ 200) do
    Keepsakes.Staff.authorize!(scope, "audit.view")

    from(e in Event, order_by: [desc: e.inserted_at], limit: ^limit)
    |> filter(:action, filters["action"])
    |> filter(:actor, filters["actor"])
    |> filter(:target_id, filters["target_id"])
    |> Repo.all()
  end

  defp filter(query, _key, value) when value in [nil, ""], do: query
  defp filter(query, :action, value), do: where(query, [e], like(e.action, ^"#{value}%"))
  defp filter(query, :actor, value), do: where(query, [e], ilike(e.actor_email, ^"%#{value}%"))
  defp filter(query, :target_id, value), do: where(query, [e], e.target_id == ^value)

  @doc "Action prefixes seen in the log, for the filter."
  def action_groups do
    from(e in Event, select: fragment("split_part(?, '.', 1)", e.action), distinct: true)
    |> Repo.all()
    |> Enum.sort()
  end
end
