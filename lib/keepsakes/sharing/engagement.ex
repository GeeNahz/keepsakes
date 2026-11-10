defmodule Keepsakes.Sharing.Engagement do
  @moduledoc """
  What guests can do besides looking: add photos (for approval), leave
  hearts on photos, and sign the guestbook (for approval).

  Each is a switch on the share link that the owner turns on, and works
  only while the owner's flags and plan include it (`available/1`); turning
  a feature off, or a downgrade, hides it without deleting anything.

  Guests are told apart by a random `visitor_key` kept in their session
  when they unlock the link (`KeepsakesWeb.GuestAccess`): one heart per
  photo, rate limits, and seeing their own pending note.

  Hearts are broadcast on the album's guest topic (`subscribe/1`) as
  `{:hearts, memory_id, count}`; owner-side counts of waiting photos and
  notes go out as `{:albums_changed, owner_id}` on the owner's topic.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.Sharing.{GuestbookEntry, Reaction, ShareLink}
  alias Keepsakes.{Entitlements, Flags, RateLimit, Repo}

  @uploads_per_hour 20
  @notes_per_hour 3

  ## What the owner has

  @doc """
  Each engagement feature for the album owner: `:ok`, `:flag_off` or
  `:not_in_plan`. Time capsule is plan-only (no flag).
  """
  @spec available(Scope.t()) :: %{atom() => :ok | :flag_off | :not_in_plan}
  def available(%Scope{user: user} = scope) do
    for key <- [:guest_uploads, :reactions_guestbook, :slideshow_music, :time_capsule],
        into: %{} do
      cond do
        key != :time_capsule and not Flags.enabled?(key, user) -> {key, :flag_off}
        not Entitlements.can?(scope, key) -> {key, :not_in_plan}
        true -> {key, :ok}
      end
    end
  end

  @doc """
  Saves the link's engagement switches; any the owner doesn't have stay
  as they were (on switches can only be turned off).
  """
  @spec update_features(Scope.t(), ShareLink.t(), map()) ::
          {:ok, ShareLink.t()} | {:error, Ecto.Changeset.t()}
  def update_features(
        %Scope{user: %{id: user_id}} = scope,
        %ShareLink{user_id: user_id} = link,
        attrs
      ) do
    available = available(scope)

    changeset =
      Enum.reduce(
        [:guest_uploads, :reactions_guestbook, :slideshow_music],
        ShareLink.features_changeset(link, attrs),
        fn key, cs ->
          if available[key] != :ok and Ecto.Changeset.get_change(cs, key) == true,
            do: Ecto.Changeset.delete_change(cs, key),
            else: cs
        end
      )

    Repo.update(changeset)
  end

  @doc "Whether guests of `link` may add photos now."
  @spec uploads_open?(ShareLink.t()) :: boolean()
  def uploads_open?(%ShareLink{guest_uploads: true} = link), do: owner_has?(link, :guest_uploads)
  def uploads_open?(_link), do: false

  @doc "Whether guests of `link` may leave hearts and guestbook notes now."
  @spec reactions_open?(ShareLink.t()) :: boolean()
  def reactions_open?(%ShareLink{reactions_guestbook: true} = link),
    do: owner_has?(link, :reactions_guestbook)

  def reactions_open?(_link), do: false

  defp owner_has?(%ShareLink{user: %{} = owner}, key),
    do: Flags.enabled?(key, owner) and Entitlements.can?(owner.id, key)

  defp owner_has?(%ShareLink{user_id: user_id} = link, key),
    do: owner_has?(%{link | user: Repo.get!(Keepsakes.Accounts.User, user_id)}, key)

  ## Guest uploads

  @doc """
  A guest adds a photo to the link's album. `attrs` has `:guest_name`
  (required) and optional `:title`, `:month`, `:year`, `:caption`; the
  guest has ticked the rights box. Errors: `:closed`, `:name`,
  `{:rate_limited, ms}` or the owner's plan limits.
  """
  @spec add_photo(ShareLink.t(), String.t(), map(), map()) :: {:ok, Memory.t()} | {:error, term()}
  def add_photo(%ShareLink{} = link, visitor_key, upload, attrs) do
    name =
      attrs |> Map.get(:guest_name, "") |> to_string() |> String.trim() |> String.slice(0, 60)

    cond do
      not uploads_open?(link) ->
        {:error, :closed}

      name == "" ->
        {:error, :name}

      true ->
        with :ok <- rate_limit("guest_upload:#{link.id}:#{visitor_key}", @uploads_per_hour) do
          Albums.create_guest_memory(
            link.album,
            upload,
            clean_details(%{attrs | guest_name: name})
          )
        end
    end
  end

  defp clean_details(attrs) do
    changeset = Memory.changeset(%Memory{}, Map.take(attrs, [:title, :month, :year, :caption]))

    Map.merge(
      %{guest_name: attrs.guest_name},
      if(changeset.valid?,
        do: Map.take(changeset.changes, [:title, :month, :year, :caption]),
        else: %{}
      )
    )
  end

  ## Hearts

  @doc "Subscribes a guest page to the album's hearts."
  def subscribe(%Album{id: id}), do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, topic(id))

  defp topic(album_id), do: "album:#{album_id}:guests"

  @doc "Hearts per photo in the album, as `%{memory_id => count}`."
  @spec heart_counts(Album.t()) :: %{Ecto.UUID.t() => pos_integer()}
  def heart_counts(%Album{id: album_id}) do
    from(r in Reaction,
      join: m in assoc(r, :memory),
      where: m.album_id == ^album_id,
      group_by: r.memory_id,
      select: {r.memory_id, count(r.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Photos this guest has hearted, as a `MapSet` of ids."
  def hearted(%Album{id: album_id}, visitor_key) when is_binary(visitor_key) do
    from(r in Reaction,
      join: m in assoc(r, :memory),
      where: m.album_id == ^album_id and r.visitor_key == ^visitor_key,
      select: r.memory_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def hearted(_album, _visitor_key), do: MapSet.new()

  @doc """
  Adds the guest's heart to a photo they can see, or takes it back.
  Returns `{:ok, hearted?, count}`.
  """
  @spec toggle_heart(ShareLink.t(), String.t(), String.t()) ::
          {:ok, boolean(), non_neg_integer()} | {:error, :closed | :not_found}
  def toggle_heart(%ShareLink{} = link, visitor_key, memory_id) when is_binary(visitor_key) do
    with true <- reactions_open?(link) || {:error, :closed},
         %Memory{} = memory <-
           Keepsakes.Sharing.guest_memory(link.album, memory_id) || {:error, :not_found} do
      existing = Repo.get_by(Reaction, memory_id: memory.id, visitor_key: visitor_key)

      hearted? =
        if existing do
          Repo.delete!(existing)
          false
        else
          %Reaction{memory_id: memory.id, share_link_id: link.id, visitor_key: visitor_key}
          |> Repo.insert(on_conflict: :nothing)

          true
        end

      count = Repo.aggregate(from(r in Reaction, where: r.memory_id == ^memory.id), :count)

      Phoenix.PubSub.broadcast(
        Keepsakes.PubSub,
        topic(memory.album_id),
        {:hearts, memory.id, count}
      )

      {:ok, hearted?, count}
    end
  end

  def toggle_heart(_link, _visitor_key, _memory_id), do: {:error, :closed}

  ## Guestbook

  @spec change_note(map()) :: Ecto.Changeset.t()
  def change_note(attrs \\ %{}), do: GuestbookEntry.changeset(%GuestbookEntry{}, attrs)

  @doc "Approved notes, newest first, plus this guest's own pending ones."
  @spec guestbook(Album.t(), String.t() | nil) :: [GuestbookEntry.t()]
  def guestbook(%Album{id: album_id}, visitor_key) do
    from(e in GuestbookEntry,
      where: e.album_id == ^album_id,
      where:
        e.status == "approved" or
          (e.status == "pending" and e.visitor_key == ^(visitor_key || "")),
      order_by: [desc: e.inserted_at, desc: e.id]
    )
    |> Repo.all()
  end

  @doc "A guest signs the guestbook; the note waits for approval."
  @spec sign(ShareLink.t(), String.t(), map()) ::
          {:ok, GuestbookEntry.t()}
          | {:error, Ecto.Changeset.t() | :closed | {:rate_limited, integer()}}
  def sign(%ShareLink{} = link, visitor_key, attrs) when is_binary(visitor_key) do
    changeset =
      %GuestbookEntry{album_id: link.album_id, share_link_id: link.id, visitor_key: visitor_key}
      |> GuestbookEntry.changeset(attrs)

    cond do
      not reactions_open?(link) ->
        {:error, :closed}

      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      true ->
        with :ok <- rate_limit("guestbook:#{link.id}:#{visitor_key}", @notes_per_hour),
             {:ok, entry} <- Repo.insert(changeset) do
          notify_guestbook(link.user_id, link.album_id)
          {:ok, entry}
        end
    end
  end

  @doc "Notes waiting for approval, oldest first (owner or editor)."
  @spec pending_notes(Scope.t(), Album.t()) :: [GuestbookEntry.t()]
  def pending_notes(%Scope{} = scope, %Album{} = album) do
    :ok = Albums.authorize!(scope, album, :edit)

    from(e in GuestbookEntry,
      where: e.album_id == ^album.id and e.status == "pending",
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Approved notes, newest first, for the owner's album page."
  @spec approved_notes(Scope.t(), Album.t()) :: [GuestbookEntry.t()]
  def approved_notes(%Scope{} = scope, %Album{} = album) do
    :ok = Albums.authorize!(scope, album, :view)

    from(e in GuestbookEntry,
      where: e.album_id == ^album.id and e.status == "approved",
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Shows a note to everyone."
  def approve_note(%Scope{} = scope, %Album{} = album, id) do
    :ok = Albums.authorize!(scope, album, :edit)

    {:ok, entry} =
      Repo.get_by!(GuestbookEntry, id: id, album_id: album.id)
      |> Ecto.Changeset.change(status: "approved")
      |> Repo.update()

    notify_guestbook(album.user_id, album.id)
    {:ok, entry}
  end

  @doc "Deletes a note (declining a pending one, or removing an approved one)."
  def delete_note(%Scope{} = scope, %Album{} = album, id) do
    :ok = Albums.authorize!(scope, album, :edit)
    {:ok, entry} = Repo.get_by!(GuestbookEntry, id: id, album_id: album.id) |> Repo.delete()
    notify_guestbook(album.user_id, album.id)
    {:ok, entry}
  end

  @doc "Pending guest photos and notes per album of the owner (digest email)."
  @spec waiting_for_owner(Ecto.UUID.t()) :: %{photos: non_neg_integer(), notes: non_neg_integer()}
  def waiting_for_owner(user_id) do
    photos =
      Repo.aggregate(
        from(m in Memory, where: m.user_id == ^user_id and m.status == "submitted"),
        :count
      )

    notes =
      Repo.aggregate(
        from(e in GuestbookEntry,
          join: a in assoc(e, :album),
          where: a.user_id == ^user_id and e.status == "pending"
        ),
        :count
      )

    %{photos: photos, notes: notes}
  end

  @doc "Pending notes in the album."
  def pending_notes_count(%Album{id: album_id}),
    do:
      Repo.aggregate(
        from(e in GuestbookEntry, where: e.album_id == ^album_id and e.status == "pending"),
        :count
      )

  ## Helpers

  defp rate_limit(key, per_hour) do
    case RateLimit.check(key, :timer.hours(1), per_hour) do
      :ok -> :ok
      {:error, {:rate_limited, ms}} -> {:error, {:rate_limited, ms}}
    end
  end

  # The owner's and collaborators' album pages reload their review lists;
  # guest pages reload the guestbook
  defp notify_guestbook(user_id, album_id) do
    message = {:guestbook_changed, album_id}
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, "user:#{user_id}:albums", message)
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, "album:#{album_id}", message)
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, topic(album_id), message)
  end
end
