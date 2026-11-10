defmodule Keepsakes.Flags do
  @moduledoc """
  Feature flags, for turning a feature on gradually: off, on for chosen
  customers (beta testers), or on for everyone. Stored by FunWithFlags in
  Postgres and cached on every node.

  Flags are declared here, so the admin portal can describe each one and
  code can only ask about flags that exist. Each gates a feature that's
  still being built; the feature checks `enabled?/2` once it lands.
  Changing a flag needs `flags.manage` and is audited.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.User
  alias Keepsakes.{Audit, Repo, Staff}
  alias Keepsakes.Staff.Scope

  @flags [
    {:custom_domains, "Custom domains",
     "Customers can connect their own domain to their albums (Stage 8)."},
    {:guest_uploads, "Guest uploads",
     "Guests can add photos to an album through a QR link, for the owner to approve (Stage 9)."},
    {:slideshow_music, "Slideshow music",
     "Owners can pick music for the guest slideshow (Stage 9)."},
    {:reactions_guestbook, "Reactions and guestbook",
     "Guests can leave hearts and guestbook notes (Stage 9)."}
  ]

  @keys Enum.map(@flags, &elem(&1, 0))

  @doc "Declared flags as `%{key, name, description}`."
  def all, do: for({key, name, desc} <- @flags, do: %{key: key, name: name, description: desc})

  @doc "Flag keys."
  def keys, do: @keys

  @doc "Whether `flag` is on for `user` (or for everyone, without a user)."
  def enabled?(flag, user \\ nil) when flag in @keys do
    case user do
      %User{} -> FunWithFlags.enabled?(flag, for: user)
      nil -> FunWithFlags.enabled?(flag)
    end
  end

  @doc "`:everyone`, `:chosen` or `:off`, with the chosen customers."
  def state(flag) when flag in @keys do
    {:ok, %{gates: gates}} = FunWithFlags.get_flag(flag) |> wrap()
    everyone? = Enum.any?(gates, &(&1.type == :boolean and &1.enabled))

    user_ids =
      for %{type: :actor, enabled: true, for: "user:" <> id} <- gates, do: id

    users =
      if user_ids == [],
        do: [],
        else: Repo.all(from u in User, where: u.id in ^user_ids, order_by: u.email)

    cond do
      everyone? -> {:everyone, users}
      users != [] -> {:chosen, users}
      true -> {:off, users}
    end
  end

  defp wrap(%FunWithFlags.Flag{} = flag), do: {:ok, flag}
  defp wrap(_), do: {:ok, %{gates: []}}

  @doc """
  Sets a flag to `:everyone`, `:chosen` (only the customers added with
  `add_customer/3`) or `:off` (also forgets the chosen customers).
  """
  def set(%Scope{} = scope, flag, to) when flag in @keys and to in [:everyone, :chosen, :off] do
    Staff.authorize!(scope, "flags.manage")
    {before, _} = state(flag)

    case to do
      :everyone -> {:ok, true} = FunWithFlags.enable(flag)
      :chosen -> {:ok, false} = FunWithFlags.disable(flag)
      :off -> :ok = FunWithFlags.clear(flag)
    end

    audit(scope, flag, %{"before" => to_string(before), "after" => to_string(to)})
  end

  @doc "Turns the flag on for the customer with `email` (they must exist)."
  def add_customer(%Scope{} = scope, flag, email) when flag in @keys do
    Staff.authorize!(scope, "flags.manage")

    case Repo.get_by(User, email: String.downcase(String.trim(email || ""))) do
      nil ->
        {:error, :no_account}

      user ->
        {:ok, true} = FunWithFlags.enable(flag, for_actor: user)
        audit(scope, flag, %{"added" => user.email})
        {:ok, user}
    end
  end

  @doc "Takes a customer off the flag."
  def remove_customer(%Scope{} = scope, flag, %User{} = user) when flag in @keys do
    Staff.authorize!(scope, "flags.manage")
    :ok = FunWithFlags.clear(flag, for_actor: user)
    audit(scope, flag, %{"removed" => user.email})
    :ok
  end

  defp audit(scope, flag, changes) do
    Audit.record(scope, "flag.changed", {"flag", flag, to_string(flag)}, changes)
    :ok
  end
end
