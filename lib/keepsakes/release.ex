defmodule Keepsakes.Release do
  @moduledoc """
  Tasks run inside a release, where Mix isn't available:

      bin/keepsakes eval "Keepsakes.Release.storage_check()"
      bin/keepsakes eval 'Keepsakes.Release.grant_staff("you@example.com", "super_admin")'
  """

  @app :keepsakes

  @doc """
  Gives an existing account staff access with the role `role_key` (keeping
  any roles it has). Returns `:ok` or `{:error, message}`.
  """
  def grant_staff(email, role_key) do
    {:ok, _} = Application.ensure_all_started(@app)
    alias Keepsakes.{Repo, Staff}

    case Repo.get_by(Staff.Role, key: role_key) do
      nil ->
        {:error, "No role called #{role_key}"}

      role ->
        current =
          with %{} = user <- Repo.get_by(Keepsakes.Accounts.User, email: String.downcase(email)),
               %{roles: roles} <- Staff.get_membership(user),
               do: Enum.map(roles, & &1.id),
               else: (_ -> [])

        case Staff.grant(:system, email, Enum.uniq([role.id | current])) do
          {:ok, _} -> :ok
          {:error, :no_account} -> {:error, "No account for #{email}; sign up first"}
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end

  @doc """
  Runs `Keepsakes.Storage.Check` and prints each step with `print`.
  Returns `true` when every step passed.
  """
  @spec storage_check((String.t() -> any())) :: boolean()
  def storage_check(print \\ &IO.puts/1) do
    {:ok, _} = Application.ensure_all_started(@app)

    print.("Checking #{Keepsakes.Storage.Check.describe()}")
    {status, steps} = Keepsakes.Storage.Check.run()
    Enum.each(Keepsakes.Storage.Check.format(steps), print)
    print.(if status == :ok, do: "Storage OK", else: "Storage check FAILED")

    status == :ok
  end
end
