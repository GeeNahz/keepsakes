defmodule Keepsakes.Albums.Members do
  @moduledoc """
  Collaborators: the owner invites people to an album by email as an
  editor or a viewer (`Keepsakes.Albums.Member`).

  Seats (`collaborator_seats` on the owner's plan) count distinct people
  across all the owner's albums, invited or joined, so the same person on
  two albums uses one seat. Going over after a downgrade removes nobody;
  it only stops new invitations.

  The invitation email links to `/invites/:token` (only a hash of the
  token is stored). It's valid for 14 days and for the invited email
  only; resending makes a new link.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Albums
  alias Keepsakes.Albums.{Album, Member, Notifier}
  alias Keepsakes.{Entitlements, Repo}

  @valid_days 14

  @doc "The album's members, joined first, then pending invitations."
  @spec list(Scope.t(), Album.t()) :: [Member.t()]
  def list(%Scope{} = scope, %Album{} = album) do
    :ok = Albums.authorize!(scope, album, :manage)

    from(m in Member,
      where: m.album_id == ^album.id,
      order_by: [asc_nulls_last: m.accepted_at, asc: m.invited_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc "Distinct people invited to or on any of the owner's albums."
  @spec seats_used(Scope.t()) :: non_neg_integer()
  def seats_used(%Scope{user: user}) do
    from(m in Member,
      join: a in assoc(m, :album),
      where: a.user_id == ^user.id,
      select: count(m.email, :distinct)
    )
    |> Repo.one()
  end

  @doc "The owner's seat limit (`:unlimited` or a number)."
  def seat_limit(%Scope{} = scope), do: Entitlements.limit(scope, :collaborator_seats)

  @spec change_invite(map()) :: Ecto.Changeset.t()
  def change_invite(attrs \\ %{}), do: Member.invite_changeset(%Member{role: "editor"}, attrs)

  @doc """
  Invites `attrs["email"]` to the album as `attrs["role"]` and emails them.
  Fails with a changeset (bad email, already invited, the owner's own
  email) or `{:over_limit, :collaborator_seats, used, max}`.
  """
  @spec invite(Scope.t(), Album.t(), map()) ::
          {:ok, Member.t()} | {:error, Ecto.Changeset.t() | Entitlements.over_limit()}
  def invite(%Scope{user: owner} = scope, %Album{} = album, attrs) do
    :ok = Albums.authorize!(scope, album, :manage)
    changeset = Member.invite_changeset(%Member{}, attrs)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      Ecto.Changeset.get_field(changeset, :email) == String.downcase(owner.email) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(:email, "is your own account")
         |> Map.put(:action, :insert)}

      true ->
        insert_invite(scope, album, changeset)
    end
  end

  defp insert_invite(%Scope{user: owner} = scope, album, changeset) do
    email = Ecto.Changeset.get_field(changeset, :email)
    {token, hash} = new_token()

    Repo.transaction(fn ->
      :ok = Entitlements.lock(scope)

      # Someone already on another of the owner's albums uses no new seat
      new_person? = not has_person?(owner, email)

      with :ok <-
             if(new_person?,
               do: Entitlements.check(scope, :collaborator_seats, seats_used(scope)),
               else: :ok
             ),
           {:ok, member} <-
             changeset
             |> Ecto.Changeset.change(
               album_id: album.id,
               invited_by_id: owner.id,
               token_hash: hash,
               invited_at: DateTime.utc_now(:second)
             )
             |> Repo.insert() do
        member
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, member} ->
        Notifier.deliver_invite(member, album, owner, invite_url(token))
        {:ok, member}

      error ->
        error
    end
  end

  defp has_person?(%User{id: owner_id}, email) do
    Repo.exists?(
      from m in Member,
        join: a in assoc(m, :album),
        where: a.user_id == ^owner_id and m.email == ^email
    )
  end

  @doc "Sends a pending invitation again, with a new link."
  @spec resend(Scope.t(), Album.t(), Member.t()) :: {:ok, Member.t()} | {:error, :already_joined}
  def resend(%Scope{user: owner} = scope, %Album{} = album, %Member{} = member) do
    :ok = Albums.authorize!(scope, album, :manage)
    member = Repo.get_by!(Member, id: member.id, album_id: album.id)

    if Member.accepted?(member) do
      {:error, :already_joined}
    else
      {token, hash} = new_token()

      {:ok, member} =
        member
        |> Ecto.Changeset.change(token_hash: hash, invited_at: DateTime.utc_now(:second))
        |> Repo.update()

      Notifier.deliver_invite(member, album, owner, invite_url(token))
      {:ok, member}
    end
  end

  @doc "Changes a member's role (`\"editor\"` or `\"viewer\"`)."
  @spec change_role(Scope.t(), Album.t(), Member.t(), String.t()) ::
          {:ok, Member.t()} | {:error, Ecto.Changeset.t()}
  def change_role(%Scope{} = scope, %Album{} = album, %Member{} = member, role) do
    :ok = Albums.authorize!(scope, album, :manage)

    Repo.get_by!(Member, id: member.id, album_id: album.id)
    |> Member.role_changeset(%{role: role})
    |> Repo.update()
    |> tap(&notify_member/1)
  end

  @doc "Removes a member or cancels an invitation."
  @spec remove(Scope.t(), Album.t(), Member.t()) :: {:ok, Member.t()}
  def remove(%Scope{} = scope, %Album{} = album, %Member{} = member) do
    :ok = Albums.authorize!(scope, album, :manage)

    Repo.get_by!(Member, id: member.id, album_id: album.id)
    |> Repo.delete()
    |> tap(&notify_member/1)
  end

  @doc "The caller leaves an album they joined."
  @spec leave(Scope.t(), Album.t()) :: :ok
  def leave(%Scope{user: user}, %Album{id: album_id}) do
    from(m in Member, where: m.album_id == ^album_id and m.user_id == ^user.id)
    |> Repo.delete_all()

    broadcast_shared(user.id)
    :ok
  end

  ## Accepting

  @doc """
  The pending invitation for `token`, with its album and owner, or `nil`
  (unknown, expired or already used).
  """
  @spec get_invite(String.t()) :: Member.t() | nil
  def get_invite(token) when is_binary(token) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@valid_days, :day)

    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         %Member{} = member <-
           from(m in Member,
             where:
               m.token_hash == ^hash(raw) and is_nil(m.accepted_at) and m.invited_at > ^cutoff,
             preload: [album: :user]
           )
           |> Repo.one() do
      member
    else
      _ -> nil
    end
  end

  def get_invite(_token), do: nil

  @doc """
  Joins the album for the signed-in account. The account's email must be
  the invited one. Returns the album.
  """
  @spec accept(Scope.t(), String.t()) ::
          {:ok, Album.t()} | {:error, :invalid | {:wrong_account, String.t()}}
  def accept(%Scope{user: user}, token) do
    case get_invite(token) do
      nil ->
        {:error, :invalid}

      %Member{email: email} = member ->
        if String.downcase(user.email) == email do
          {:ok, _} =
            member
            |> Ecto.Changeset.change(
              user_id: user.id,
              accepted_at: DateTime.utc_now(:second),
              token_hash: nil
            )
            |> Repo.update()

          broadcast_shared(user.id)
          {:ok, member.album}
        else
          {:error, {:wrong_account, email}}
        end
    end
  end

  @doc "How many collaborators (invited or joined) an owner has, for staff."
  def count_for_owner(user_id), do: seats_used(%Scope{user: %User{id: user_id}})

  ## Helpers

  # A joined member's sidebar ("Shared with me") follows role changes and removal
  defp notify_member({:ok, %Member{user_id: user_id}}) when is_binary(user_id),
    do: broadcast_shared(user_id)

  defp notify_member(_result), do: :ok

  defp broadcast_shared(user_id) do
    Phoenix.PubSub.broadcast(
      Keepsakes.PubSub,
      "user:#{user_id}:albums",
      {:albums_changed, user_id}
    )
  end

  defp new_token do
    raw = :crypto.strong_rand_bytes(32)
    {Base.url_encode64(raw, padding: false), hash(raw)}
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)

  defp invite_url(token), do: KeepsakesWeb.Endpoint.url() <> "/invites/" <> token
end
