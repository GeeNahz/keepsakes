defmodule Keepsakes.Domains.Admin do
  @moduledoc """
  Customers' domains as staff see them (`domains.manage`): every domain
  with its owner and last check, checking again, blocking (the site stops
  at once) and unblocking, and the list of names nobody may use. Blocking
  a name also blocks any domain that already matches it. Audited.
  """
  import Ecto.Query

  alias Keepsakes.Domains.{BlockedHostname, Domain}
  alias Keepsakes.{Audit, Domains, Repo, Staff}
  alias Keepsakes.Staff.Scope

  @doc "Domains, newest first, filtered by `\"status\"` and `\"q\"` (hostname or owner email)."
  def list(%Scope{} = scope, filters \\ %{}) do
    Staff.authorize!(scope, "domains.manage")

    from(d in Domain,
      join: u in assoc(d, :user),
      as: :user,
      order_by: [desc: d.inserted_at],
      preload: [user: u]
    )
    |> filter(:status, filters["status"])
    |> filter(:q, filters["q"])
    |> Repo.all()
  end

  defp filter(query, _key, value) when value in [nil, ""], do: query
  defp filter(query, :status, status), do: where(query, [d], d.status == ^status)

  defp filter(query, :q, q) do
    like = "%" <> String.replace(String.trim(q), ~r/[\\%_]/, "\\\\\\0") <> "%"
    where(query, [d, user: u], ilike(d.hostname, ^like) or ilike(u.email, ^like))
  end

  def get!(%Scope{} = scope, id) do
    Staff.authorize!(scope, "domains.manage")
    Repo.one!(from d in Domain, where: d.id == ^id, preload: :user)
  end

  @doc "Checks the domain's DNS now."
  def check(%Scope{} = scope, %Domain{} = domain) do
    Staff.authorize!(scope, "domains.manage")
    {:ok, checked} = Domains.check(domain)
    audit(scope, "domain.checked", domain, %{"result" => checked.status})
    {:ok, checked}
  end

  @doc "Stops the domain's site straight away, with a reason."
  def block(%Scope{} = scope, %Domain{} = domain, reason) do
    Staff.authorize!(scope, "domains.manage")
    reason = String.trim(reason || "")

    if reason == "" do
      {:error, :reason_required}
    else
      Repo.transact(fn ->
        updated =
          domain
          |> Ecto.Changeset.change(status: "blocked", blocked_reason: reason)
          |> Repo.update!()

        audit(scope, "domain.blocked", domain, %{"before" => domain.status, "reason" => reason})
        {:ok, updated}
      end)
    end
  end

  @doc "Lets the domain be checked again (it's verified on its next good check)."
  def unblock(%Scope{} = scope, %Domain{status: "blocked"} = domain) do
    Staff.authorize!(scope, "domains.manage")

    Repo.transact(fn ->
      updated =
        domain
        |> Ecto.Changeset.change(
          status: "pending",
          blocked_reason: nil,
          checks: 0,
          last_checked_at: nil
        )
        |> Repo.update!()

      audit(scope, "domain.unblocked", domain, %{})
      {:ok, updated}
    end)
  end

  def unblock(_scope, _domain), do: {:error, :not_blocked}

  ## Blocked names

  def list_blocked(%Scope{} = scope) do
    Staff.authorize!(scope, "domains.manage")
    Repo.all(from b in BlockedHostname, order_by: b.pattern)
  end

  def change_blocked(attrs \\ %{}), do: BlockedHostname.changeset(%BlockedHostname{}, attrs)

  @doc "Adds a blocked name and blocks any existing domain matching it."
  def add_blocked(%Scope{} = scope, attrs) do
    Staff.authorize!(scope, "domains.manage")

    Repo.transact(fn ->
      with {:ok, blocked} <-
             %BlockedHostname{added_by_id: scope.user.id}
             |> BlockedHostname.changeset(attrs)
             |> Repo.insert() do
        matching =
          from(d in Domain, where: d.status != "blocked")
          |> Repo.all()
          |> Enum.filter(&BlockedHostname.match?(blocked, &1.hostname))

        Enum.each(matching, fn d ->
          d
          |> Ecto.Changeset.change(status: "blocked", blocked_reason: blocked.reason)
          |> Repo.update!()
        end)

        Audit.record(
          scope,
          "blocked_hostname.added",
          {"blocked_hostname", blocked.id, blocked.pattern},
          %{
            "reason" => blocked.reason,
            "domains_blocked" => Enum.map(matching, & &1.hostname)
          }
        )

        {:ok, blocked}
      end
    end)
  end

  @doc "Removes a blocked name (domains it blocked stay blocked until unblocked)."
  def remove_blocked(%Scope{} = scope, %BlockedHostname{} = blocked) do
    Staff.authorize!(scope, "domains.manage")

    Repo.transact(fn ->
      {:ok, deleted} = Repo.delete(blocked)

      Audit.record(
        scope,
        "blocked_hostname.removed",
        {"blocked_hostname", blocked.id, blocked.pattern}
      )

      {:ok, deleted}
    end)
  end

  defp audit(scope, action, domain, changes),
    do: Audit.record(scope, action, {"domain", domain.id, domain.hostname}, changes)
end
