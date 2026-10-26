defmodule Keepsakes.Staff do
  @moduledoc """
  Staff of the admin portal: ordinary user accounts with an active
  membership and one or more roles. Permissions come from the roles;
  Super Admin (a locked system role) has them all.

  Every admin function takes a `%Keepsakes.Staff.Scope{}` and calls
  `authorize!/2` (or `authorize/2`) itself, so pages hiding a button is
  never the only check. Changes are written to the audit log in the same
  transaction.

  The first Super Admin comes from `SUPER_ADMIN_EMAIL` (granted at startup
  and when that address signs up) or `mix keepsakes.staff.grant`.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.User
  alias Keepsakes.{Audit, Repo}
  alias Keepsakes.Staff.{Forbidden, Membership, Permissions, Role}
  alias Keepsakes.Staff.Scope, as: StaffScope

  ## Who is staff

  @doc "The user's active membership with roles, or nil."
  def get_membership(%User{id: user_id}) do
    Repo.one(
      from m in Membership,
        where: m.user_id == ^user_id and m.active,
        preload: :roles
    )
  end

  @doc "Whether the user is active staff."
  def staff?(%User{} = user), do: not is_nil(get_membership(user))

  @doc "A staff scope for `user` (nil when they aren't active staff)."
  @spec scope_for(User.t(), String.t() | nil) :: StaffScope.t() | nil
  def scope_for(%User{} = user, ip \\ nil) do
    case get_membership(user) do
      nil ->
        nil

      membership ->
        %StaffScope{
          user: user,
          ip: ip,
          super_admin?: Enum.any?(membership.roles, & &1.system),
          permissions: membership.roles |> Enum.flat_map(& &1.permissions) |> MapSet.new()
        }
    end
  end

  @doc "User IDs of all staff (active or not), to leave out of customer metrics."
  def staff_user_ids_query, do: from(m in Membership, select: m.user_id)

  ## Checks

  @doc "`:ok` when the staff member has `permission`, else `{:error, :forbidden}`."
  def authorize(%StaffScope{} = scope, permission) do
    if StaffScope.can?(scope, permission), do: :ok, else: {:error, :forbidden}
  end

  @doc "Raises `Keepsakes.Staff.Forbidden` (403) without `permission`."
  def authorize!(%StaffScope{} = scope, permission) do
    with {:error, :forbidden} <- authorize(scope, permission), do: raise(Forbidden)
  end

  ## Staff list

  @doc "Active and inactive staff with their users and roles."
  def list_staff(%StaffScope{} = scope) do
    authorize!(scope, "roles.manage")

    from(m in Membership,
      join: u in assoc(m, :user),
      order_by: [desc: m.active, asc: u.first_name],
      preload: [:roles, user: u]
    )
    |> Repo.all()
  end

  @doc """
  Makes the account with `email` staff with `role_ids` (or updates an
  existing membership's roles and reactivates it). The account must exist.
  """
  @spec grant(StaffScope.t() | :system, String.t(), [Ecto.UUID.t()]) ::
          {:ok, Membership.t()} | {:error, :no_account | :no_roles | :forbidden}
  def grant(actor, email, role_ids) do
    with :ok <- authorize_actor(actor, "roles.manage"),
         %User{} = user <-
           Repo.get_by(User, email: String.downcase(String.trim(email))) || {:error, :no_account},
         [_ | _] = roles <-
           Repo.all(from r in Role, where: r.id in ^role_ids) || {:error, :no_roles},
         membership =
           (Repo.get_by(Membership, user_id: user.id) || %Membership{user_id: user.id})
           |> Repo.preload(:roles),
         :ok <- guard_super_admin(actor, roles ++ membership.roles) do
      Repo.transact(fn ->
        before = role_names(membership.roles)

        {:ok, membership} =
          membership
          |> Ecto.Changeset.change(active: true, added_by_id: actor_id(actor))
          |> Ecto.Changeset.put_assoc(:roles, roles)
          |> Repo.insert_or_update()

        Audit.record(actor, "staff.granted", {"user", user.id, user.email}, %{
          "before" => before,
          "after" => role_names(roles)
        })

        {:ok, Repo.preload(membership, :user)}
      end)
    else
      [] -> {:error, :no_roles}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Ends someone's staff access (their customer account stays)."
  def revoke(%StaffScope{} = scope, %Membership{} = membership) do
    authorize!(scope, "roles.manage")
    membership = Repo.preload(membership, [:user, :roles])

    cond do
      membership.user_id == scope.user.id ->
        {:error, :self}

      guard_super_admin(scope, membership.roles) != :ok ->
        {:error, :forbidden}

      last_super_admin?(membership) ->
        {:error, :last_super_admin}

      true ->
        Repo.transact(fn ->
          {:ok, membership} = membership |> Ecto.Changeset.change(active: false) |> Repo.update()

          Audit.record(
            scope,
            "staff.revoked",
            {"user", membership.user_id, membership.user.email},
            %{
              "roles" => role_names(membership.roles)
            }
          )

          {:ok, membership}
        end)
    end
  end

  defp last_super_admin?(%Membership{roles: roles, active: true} = membership) do
    Enum.any?(roles, & &1.system) and
      Repo.aggregate(
        from(m in Membership,
          join: r in assoc(m, :roles),
          where: m.active and r.system and m.id != ^membership.id
        ),
        :count
      ) == 0
  end

  defp last_super_admin?(_membership), do: false

  # Only a Super Admin can hand out, change or take away Super Admin
  # (`roles`: the roles being granted plus the ones the person holds now)
  defp guard_super_admin(:system, _roles), do: :ok

  defp guard_super_admin(%StaffScope{super_admin?: true}, _roles), do: :ok

  defp guard_super_admin(_scope, roles),
    do: if(Enum.any?(roles, & &1.system), do: {:error, :forbidden}, else: :ok)

  defp authorize_actor(:system, _permission), do: :ok
  defp authorize_actor(scope, permission), do: authorize(scope, permission)

  defp actor_id(:system), do: nil
  defp actor_id(%StaffScope{user: user}), do: user.id

  defp role_names(roles), do: roles |> Enum.map(& &1.name) |> Enum.sort()

  ## Roles

  def list_roles(%StaffScope{} = scope) do
    authorize!(scope, "roles.manage")
    Repo.all(from r in Role, order_by: [desc: r.system, asc: r.name])
  end

  @doc "All roles for pickers (no permission needed beyond seeing the staff page)."
  def all_roles, do: Repo.all(from r in Role, order_by: [desc: r.system, asc: r.name])

  def get_role!(%StaffScope{} = scope, id) do
    authorize!(scope, "roles.manage")
    Repo.get!(Role, id)
  end

  def change_role(%Role{} = role, attrs \\ %{}), do: Role.changeset(role, attrs)

  def create_role(%StaffScope{} = scope, attrs) do
    authorize!(scope, "roles.manage")

    Repo.transact(fn ->
      with {:ok, role} <- %Role{} |> Role.changeset(attrs) |> Repo.insert() do
        Audit.record(scope, "role.created", {"role", role.id, role.name}, %{
          "permissions" => role.permissions
        })

        {:ok, role}
      end
    end)
  end

  def update_role(%StaffScope{} = scope, %Role{system: false} = role, attrs) do
    authorize!(scope, "roles.manage")

    Repo.transact(fn ->
      with {:ok, updated} <- role |> Role.changeset(attrs) |> Repo.update() do
        Audit.record(scope, "role.updated", {"role", role.id, updated.name}, %{
          "before" => %{"name" => role.name, "permissions" => role.permissions},
          "after" => %{"name" => updated.name, "permissions" => updated.permissions}
        })

        {:ok, updated}
      end
    end)
  end

  def update_role(_scope, %Role{system: true}, _attrs), do: {:error, :locked}

  def delete_role(%StaffScope{} = scope, %Role{system: false} = role) do
    authorize!(scope, "roles.manage")

    Repo.transact(fn ->
      {:ok, role} = Repo.delete(role)

      Audit.record(scope, "role.deleted", {"role", role.id, role.name}, %{
        "permissions" => role.permissions
      })

      {:ok, role}
    end)
  end

  def delete_role(_scope, %Role{system: true}), do: {:error, :locked}

  @doc "How many active staff hold each role, as `%{role_id => count}`."
  def role_member_counts do
    from(m in Membership,
      join: r in assoc(m, :roles),
      where: m.active,
      group_by: r.id,
      select: {r.id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  ## Bootstrap

  @doc """
  Makes `email` a Super Admin if that account exists (for
  `SUPER_ADMIN_EMAIL` and `mix keepsakes.staff.grant`). Returns
  `{:ok, membership}`, `{:error, :no_account}` or `:already`.
  """
  def ensure_super_admin(email) when is_binary(email) and email != "" do
    super_admin = Repo.get_by!(Role, key: "super_admin")

    case Repo.get_by(User, email: String.downcase(String.trim(email))) do
      nil ->
        {:error, :no_account}

      user ->
        case get_membership(user) do
          %Membership{roles: roles} ->
            if Enum.any?(roles, & &1.system),
              do: :already,
              else: grant(:system, email, [super_admin.id | Enum.map(roles, & &1.id)])

          nil ->
            grant(:system, email, [super_admin.id])
        end
    end
  end

  def ensure_super_admin(_email), do: {:error, :no_account}

  @doc "Grants `SUPER_ADMIN_EMAIL` Super Admin when it's set (startup, sign-up)."
  def ensure_configured_super_admin do
    case Application.get_env(:keepsakes, :super_admin_email) do
      email when is_binary(email) and email != "" -> ensure_super_admin(email)
      _ -> :not_configured
    end
  end

  @doc "Every permission, for display (Super Admin's list)."
  def all_permissions, do: Permissions.all()
end
