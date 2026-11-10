defmodule Keepsakes.Albums do
  @moduledoc """
  Albums and their memories, scoped by the caller's `%Scope{}`.

  Every album belongs to one owner (`album.user_id`), and so do its
  memories, whoever added them: storage and plan limits are always the
  owner's. Collaborators (`Keepsakes.Albums.Members`) get a role on
  albums they've joined; `role/2` says what the caller is and each
  function checks the permission it needs:

    * `:view` - owner, editor or viewer
    * `:edit` - owner or editor (photos, drafts, cover, guest review)
    * `:manage` - owner only (sharing, template, people, deleting)

  Anyone else gets `Keepsakes.Albums.NotAllowed` (a 404).

  Changes are broadcast on the owner's topic (`subscribe/1`: sidebar,
  storage meter, the owner's album page) and memory changes also on the
  album's topic (`subscribe_album/1`: collaborators' album page),
  including when the media pipeline finishes a photo:

    * `{:memory_updated, %Memory{}}`
    * `{:memory_deleted, %Memory{}}`
    * `{:albums_changed, user_id}`
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts.{Scope, User}
  alias Keepsakes.Albums.{Album, Member, Memory, NotAllowed}
  alias Keepsakes.Media.{ProcessMemory, Purge}
  alias Keepsakes.{Entitlements, Repo, Storage, Templates}

  ## PubSub

  @doc "Subscribes the caller to the owner's album and memory events."
  def subscribe(%Scope{user: user}),
    do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, topic(user.id))

  @doc "Subscribes to one album's memory events (collaborators' album page)."
  def subscribe_album(%Album{id: id}),
    do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, album_topic(id))

  defp topic(user_id), do: "user:#{user_id}:albums"
  defp album_topic(album_id), do: "album:#{album_id}"

  defp broadcast(user_id, message),
    do: Phoenix.PubSub.broadcast(Keepsakes.PubSub, topic(user_id), message)

  # Memory events reach the owner and anyone watching the album
  defp broadcast_memory_event(%Memory{} = memory, event) do
    broadcast(memory.user_id, {event, memory})
    Phoenix.PubSub.broadcast(Keepsakes.PubSub, album_topic(memory.album_id), {event, memory})
  end

  ## Access

  @doc """
  What the caller is on `album`: `:owner`, `:editor`, `:viewer` (an
  accepted collaborator) or `nil`.
  """
  @spec role(Scope.t() | nil, Album.t()) :: :owner | :editor | :viewer | nil
  def role(%Scope{user: %{id: user_id}}, %Album{user_id: user_id}), do: :owner

  def role(%Scope{user: %{id: user_id}}, %Album{id: album_id}) do
    from(m in Member,
      where: m.album_id == ^album_id and m.user_id == ^user_id and not is_nil(m.accepted_at),
      select: m.role
    )
    |> Repo.one()
    |> case do
      "editor" -> :editor
      "viewer" -> :viewer
      nil -> nil
    end
  end

  def role(_scope, _album), do: nil

  @doc "Whether the caller may `:view`, `:edit` or `:manage` the album."
  @spec can?(Scope.t() | nil, Album.t(), :view | :edit | :manage) :: boolean()
  def can?(scope, album, permission), do: allows?(role(scope, album), permission)

  @doc false
  def allows?(nil, _permission), do: false
  def allows?(_role, :view), do: true
  def allows?(role, :edit), do: role in [:owner, :editor]
  def allows?(role, :manage), do: role == :owner

  @doc "Raises `Keepsakes.Albums.NotAllowed` unless the caller has `permission`."
  @spec authorize!(Scope.t() | nil, Album.t(), :view | :edit | :manage) :: :ok
  def authorize!(scope, album, permission) do
    if can?(scope, album, permission), do: :ok, else: raise(NotAllowed)
  end

  @doc """
  A scope for the album's owner, for plan checks: collaborators' uploads
  count against the owner's plan and storage.
  """
  @spec owner_scope(Album.t()) :: Scope.t()
  def owner_scope(%Album{user: %User{} = owner}), do: Scope.for_user(owner)
  def owner_scope(%Album{user_id: user_id}), do: Scope.for_user(Repo.get!(User, user_id))

  defp acting_scope(%Scope{user: %{id: id}} = scope, %Album{user_id: id}), do: scope
  defp acting_scope(_scope, album), do: owner_scope(album)

  ## Albums

  @doc "The owner's albums, oldest first, with `memories_count` (published)."
  @spec list_albums(Scope.t()) :: [Album.t()]
  def list_albums(%Scope{user: user}) do
    from(a in Album,
      where: a.user_id == ^user.id,
      left_join: m in Memory,
      on: m.album_id == a.id and m.status == "published",
      group_by: a.id,
      order_by: [asc: a.inserted_at, asc: a.id],
      select_merge: %{memories_count: count(m.id)}
    )
    |> Repo.all()
  end

  @doc "The owner's album with `slug`. Raises `Ecto.NoResultsError` otherwise."
  @spec get_album_by_slug!(Scope.t(), String.t()) :: Album.t()
  def get_album_by_slug!(%Scope{user: user}, slug) do
    Repo.one!(from a in Album, where: a.user_id == ^user.id and a.slug == ^slug)
  end

  @doc """
  Albums the caller has joined as a collaborator, oldest join first, with
  the owner preloaded, `memories_count`, and the caller's `role`.
  """
  @spec list_shared_albums(Scope.t()) :: [{Album.t(), :editor | :viewer}]
  def list_shared_albums(%Scope{user: user}) do
    from(a in Album,
      join: mem in Member,
      on: mem.album_id == a.id and mem.user_id == ^user.id and not is_nil(mem.accepted_at),
      join: u in assoc(a, :user),
      left_join: m in Memory,
      on: m.album_id == a.id and m.status == "published",
      where: is_nil(u.deletion_requested_at) and is_nil(u.suspended_at),
      group_by: [a.id, mem.id, u.id],
      order_by: [asc: mem.accepted_at, asc: a.id],
      select: {%{a | memories_count: count(m.id), user: u}, mem.role}
    )
    |> Repo.all()
    |> Enum.map(fn {album, role} -> {album, String.to_existing_atom(role)} end)
  end

  @doc """
  An album the caller has joined, by id, with its owner. Raises
  `Keepsakes.Albums.NotAllowed` when the caller isn't a member (owners use
  `get_album_by_slug!/2`).
  """
  @spec get_shared_album!(Scope.t(), String.t()) :: Album.t()
  def get_shared_album!(%Scope{} = scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Album{} = album <- Repo.get(Album, uuid) |> Repo.preload(:user),
         role when role in [:editor, :viewer] <- role(scope, album),
         %User{deletion_requested_at: nil, suspended_at: nil} <- album.user do
      album
    else
      _ -> raise NotAllowed
    end
  end

  @spec change_album(Album.t(), map()) :: Ecto.Changeset.t()
  def change_album(%Album{} = album \\ %Album{}, attrs \\ %{}), do: Album.changeset(album, attrs)

  @doc """
  Creates an album for the owner with a slug unique among their albums,
  using the owner's default template. Fails with `{:over_limit, ...}`
  when the plan's album limit is reached.
  """
  @spec create_album(Scope.t(), map()) ::
          {:ok, Album.t()} | {:error, Ecto.Changeset.t() | Entitlements.over_limit()}
  def create_album(%Scope{user: user} = scope, attrs) do
    Repo.transaction(fn ->
      :ok = Entitlements.lock(scope)

      with :ok <- Entitlements.check(scope, :max_albums, album_count(scope)) do
        taken = Repo.all(from a in Album, where: a.user_id == ^user.id, select: a.slug)

        %Album{user_id: user.id, template_id: Templates.default_for(scope).id}
        |> Album.changeset(attrs)
        |> Album.put_slug(taken)
        |> Ecto.Changeset.unique_constraint(:slug, name: :albums_user_id_slug_index)
        |> Repo.insert()
      end
      |> case do
        {:ok, album} -> album
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> tap(fn
      {:ok, _} -> broadcast(user.id, {:albums_changed, user.id})
      _ -> :ok
    end)
  end

  @doc "How many albums the owner has."
  @spec album_count(Scope.t()) :: non_neg_integer()
  def album_count(%Scope{user: user}),
    do: Repo.aggregate(from(a in Album, where: a.user_id == ^user.id), :count)

  @doc "Photos (drafts included) in the owner's fullest album, for plan usage."
  @spec largest_album_count(Scope.t()) :: non_neg_integer()
  def largest_album_count(%Scope{user: user}) do
    from(m in Memory,
      where: m.user_id == ^user.id,
      group_by: m.album_id,
      select: count(m.id),
      order_by: [desc: count(m.id)],
      limit: 1
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  # Drafts count too: they're on their way into the album
  defp memory_count(%Album{id: album_id}),
    do: Repo.aggregate(from(m in Memory, where: m.album_id == ^album_id), :count)

  @doc "Makes `memory` the album cover, or clears the cover with `nil`."
  @spec set_cover(Scope.t(), Album.t(), Memory.t() | nil) :: {:ok, Album.t()}
  def set_cover(%Scope{} = scope, %Album{} = album, memory) do
    :ok = authorize!(scope, album, :edit)
    album_id = album.id

    cover_id =
      case memory do
        %Memory{album_id: ^album_id, id: id} -> id
        nil -> nil
      end

    {:ok, album} = album |> Ecto.Changeset.change(cover_memory_id: cover_id) |> Repo.update()
    broadcast(album.user_id, {:albums_changed, album.user_id})
    {:ok, album}
  end

  ## Memories

  @doc """
  Published memories in timeline order: year, then month, then position and
  upload order. Memories still missing a date go last.
  """
  @spec list_memories(Scope.t(), Album.t()) :: [Memory.t()]
  def list_memories(%Scope{} = scope, %Album{} = album) do
    album_memories(scope, album, "published")
    |> order_by([m],
      asc_nulls_last: m.year,
      asc_nulls_last: m.month,
      asc: m.position,
      asc: m.inserted_at
    )
    |> Repo.all()
  end

  @doc "Drafts still on the upload screen, in upload order."
  @spec list_drafts(Scope.t(), Album.t()) :: [Memory.t()]
  def list_drafts(%Scope{} = scope, %Album{} = album) do
    album_memories(scope, album, "draft")
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> Repo.all()
  end

  defp album_memories(%Scope{} = scope, %Album{id: album_id} = album, status) do
    :ok = authorize!(scope, album, :view)

    from m in Memory,
      where: m.user_id == ^album.user_id and m.album_id == ^album_id and m.status == ^status
  end

  @doc """
  A memory in `album` the caller can see. Raises `Ecto.NoResultsError`
  when it isn't in that album.
  """
  @spec get_memory!(Scope.t(), Album.t(), Ecto.UUID.t()) :: Memory.t()
  def get_memory!(%Scope{} = scope, %Album{} = album, id) do
    :ok = authorize!(scope, album, :view)
    Repo.one!(from m in Memory, where: m.album_id == ^album.id and m.id == ^id)
  end

  # The memory's album, checked for `permission`
  defp memory_album!(scope, %Memory{album_id: album_id}, permission) do
    album = Repo.get!(Album, album_id)
    :ok = authorize!(scope, album, permission)
    album
  end

  @doc """
  Stores an uploaded file as the original of a new draft memory and queues
  the media pipeline for it.

  `upload` is `%{path: tmp_path, filename: "IMG_2041.jpg", bytes: 6_800_000}`.

  Fails with `{:over_limit, key, used, limit}` when the photo is too big
  for the plan, or would take the album's photo count or the account's
  storage over the plan's limits (checked under the owner's limit lock).
  """
  @spec create_draft(Scope.t(), Album.t(), map()) :: {:ok, Memory.t()} | {:error, term()}
  def create_draft(%Scope{} = scope, %Album{} = album, upload) do
    :ok = authorize!(scope, album, :edit)
    # Plan limits and storage are the owner's, whoever uploads
    owner_scope = acting_scope(scope, album)

    # Checked once before storing the file (no point uploading it if it
    # can't stay) and again under the lock, where it counts
    with :ok <- check_upload(owner_scope, album, upload.bytes) do
      store_draft(owner_scope, owner_scope.user, album, upload)
    end
  end

  defp check_upload(scope, album, bytes) do
    max_mb = Entitlements.max_upload_mb(scope)

    with :ok <- if(bytes > max_mb * 1_000_000, do: too_large(max_mb), else: :ok),
         :ok <- Entitlements.check(scope, :max_memories_per_album, memory_count(album)) do
      Entitlements.check(scope, :storage_bytes, storage_used(scope), bytes)
    end
  end

  defp too_large(max_mb), do: {:error, {:over_limit, :max_upload_mb, max_mb, max_mb}}

  defp store_draft(scope, user, album, upload, fields \\ []) do
    id = Ecto.UUID.generate()

    memory =
      struct!(
        %Memory{
          id: id,
          album_id: album.id,
          user_id: user.id,
          storage_prefix: "users/#{user.id}/albums/#{album.id}/memories/#{id}",
          original_filename: upload.filename |> Path.basename() |> String.slice(0, 255),
          original_bytes: upload.bytes
        },
        fields
      )

    with :ok <- Storage.put(Memory.original_key(memory), {:file, upload.path}) do
      Multi.new()
      |> Multi.run(:limits, fn _repo, _ ->
        :ok = Entitlements.lock(scope)
        with :ok <- check_upload(scope, album, upload.bytes), do: {:ok, :within}
      end)
      |> Multi.insert(:memory, memory)
      |> Oban.insert(:job, fn %{memory: memory} -> ProcessMemory.new(%{memory_id: memory.id}) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{memory: memory}} ->
          broadcast_memory_event(memory, :memory_updated)
          broadcast(user.id, {:albums_changed, user.id})
          {:ok, memory}

        {:error, _step, reason, _} ->
          Storage.delete(Memory.original_key(memory))
          {:error, reason}
      end
    end
  end

  @doc """
  A guest's photo for the album's guest upload page
  (`Keepsakes.Sharing.add_guest_photo/4`, which checks the link, switch
  and rate limit first). It's stored as `submitted` with the guest's
  details, counts against the owner's plan at once, and shows only once
  the owner or an editor approves it.
  """
  @spec create_guest_memory(Album.t(), map(), map()) :: {:ok, Memory.t()} | {:error, term()}
  def create_guest_memory(%Album{} = album, upload, attrs) do
    owner_scope = owner_scope(album)

    fields =
      [
        status: "submitted",
        source: "guest",
        guest_name: attrs.guest_name,
        rights_confirmed_at: DateTime.utc_now(:second)
      ] ++ Enum.filter(Map.take(attrs, [:title, :month, :year, :caption]), &elem(&1, 1))

    with :ok <- check_upload(owner_scope, album, upload.bytes) do
      store_draft(owner_scope, owner_scope.user, album, upload, fields)
    end
  end

  @spec change_memory(Memory.t(), map()) :: Ecto.Changeset.t()
  def change_memory(%Memory{} = memory, attrs \\ %{}), do: Memory.changeset(memory, attrs)

  @doc "Saves edits to title, date, caption and place (owner or editor)."
  @spec update_memory(Scope.t(), Memory.t(), map()) ::
          {:ok, Memory.t()} | {:error, Ecto.Changeset.t()}
  def update_memory(%Scope{} = scope, %Memory{} = memory, attrs) do
    memory_album!(scope, memory, :edit)
    memory |> Memory.changeset(attrs) |> Repo.update() |> broadcast_memory()
  end

  @doc "Replaces the people tagged in `memory` (owner or editor)."
  @spec set_people(Scope.t(), Memory.t(), [String.t()]) ::
          {:ok, Memory.t()} | {:error, Ecto.Changeset.t()}
  def set_people(%Scope{} = scope, %Memory{} = memory, people) do
    memory_album!(scope, memory, :edit)
    memory |> Memory.people_changeset(people) |> Repo.update() |> broadcast_memory()
  end

  @doc """
  Time capsule for the whole album: guests see "Opens on …" until
  `reveal_at` (`nil` reveals it now). Owner only, on plans with
  `time_capsule`.
  """
  @spec set_reveal(Scope.t(), Album.t(), DateTime.t() | nil) ::
          {:ok, Album.t()} | {:error, :not_in_plan}
  def set_reveal(%Scope{} = scope, %Album{} = album, reveal_at) do
    :ok = authorize!(scope, album, :manage)

    if reveal_at && not Entitlements.can?(scope, :time_capsule) do
      {:error, :not_in_plan}
    else
      album
      |> Ecto.Changeset.change(reveal_at: reveal_at && DateTime.truncate(reveal_at, :second))
      |> Repo.update()
    end
  end

  @doc """
  Time capsule for one memory (owner or editor, on the owner's plan with
  `time_capsule`); `nil` reveals it now.
  """
  @spec set_memory_reveal(Scope.t(), Memory.t(), DateTime.t() | nil) ::
          {:ok, Memory.t()} | {:error, :not_in_plan}
  def set_memory_reveal(%Scope{} = scope, %Memory{} = memory, reveal_at) do
    album = memory_album!(scope, memory, :edit)

    if reveal_at && not Entitlements.can?(album.user_id, :time_capsule) do
      {:error, :not_in_plan}
    else
      memory |> Memory.reveal_changeset(reveal_at) |> Repo.update() |> broadcast_memory()
    end
  end

  @doc "Guest photos waiting for approval, oldest first (owner or editor)."
  @spec list_submitted(Scope.t(), Album.t()) :: [Memory.t()]
  def list_submitted(%Scope{} = scope, %Album{} = album) do
    :ok = authorize!(scope, album, :edit)

    from(m in Memory, where: m.album_id == ^album.id and m.status == "submitted")
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> Repo.all()
  end

  @doc "How many guest photos are waiting in the album."
  @spec submitted_count(Album.t()) :: non_neg_integer()
  def submitted_count(%Album{id: album_id}),
    do:
      Repo.aggregate(
        from(m in Memory, where: m.album_id == ^album_id and m.status == "submitted"),
        :count
      )

  @doc """
  Approves guest photos: they join the timeline as they are (editable
  like any other). `memories` defaults to every waiting photo.
  """
  @spec approve_submitted(Scope.t(), Album.t(), [Memory.t()] | :all) :: {:ok, non_neg_integer()}
  def approve_submitted(%Scope{} = scope, %Album{} = album, memories \\ :all) do
    :ok = authorize!(scope, album, :edit)

    query = from(m in Memory, where: m.album_id == ^album.id and m.status == "submitted")

    query =
      case memories do
        :all -> query
        list -> where(query, [m], m.id in ^Enum.map(list, & &1.id))
      end

    {count, approved} =
      Repo.update_all(select(query, [m], m),
        set: [status: "published", updated_at: DateTime.utc_now()]
      )

    Enum.each(approved, &broadcast_memory_event(&1, :memory_updated))
    broadcast(album.user_id, {:albums_changed, album.user_id})
    {:ok, count}
  end

  @doc """
  Publishes every draft in the album (incomplete ones included; they show
  as "needs details" until finished). The first memory on the timeline
  becomes the cover when the album has none. Returns how many were saved.
  """
  @spec publish_drafts(Scope.t(), Album.t()) :: {:ok, non_neg_integer()}
  def publish_drafts(%Scope{} = scope, %Album{} = album) do
    {count, _} =
      album_memories(scope, album, "draft")
      |> Repo.update_all(set: [status: "published", updated_at: DateTime.utc_now()])

    album = Repo.reload!(album)

    if is_nil(album.cover_memory_id) do
      case list_memories(scope, album) do
        [first | _] -> set_cover(scope, album, first)
        [] -> :ok
      end
    end

    broadcast(album.user_id, {:albums_changed, album.user_id})
    {:ok, count}
  end

  @doc "Deletes every draft in the album and their stored files."
  @spec discard_drafts(Scope.t(), Album.t()) :: {:ok, non_neg_integer()}
  def discard_drafts(%Scope{} = scope, %Album{} = album) do
    drafts = list_drafts(scope, album)
    Enum.each(drafts, &delete_memory(scope, &1))
    {:ok, length(drafts)}
  end

  @doc """
  Deletes a memory (owner or editor; also how a guest photo is declined).
  Its files are removed in the background.
  """
  @spec delete_memory(Scope.t(), Memory.t()) :: {:ok, Memory.t()} | {:error, term()}
  def delete_memory(%Scope{} = scope, %Memory{} = memory) do
    memory_album!(scope, memory, :edit)

    Multi.new()
    |> Multi.delete(:memory, memory)
    |> Oban.insert(:purge, Purge.new(%{keys: Memory.all_keys(memory)}))
    |> Repo.transaction()
    |> case do
      {:ok, %{memory: deleted}} ->
        broadcast_memory_event(deleted, :memory_deleted)
        broadcast(deleted.user_id, {:albums_changed, deleted.user_id})
        {:ok, deleted}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc "Bytes the owner is using: optimised photos plus originals still queued."
  @spec storage_used(Scope.t()) :: non_neg_integer()
  def storage_used(%Scope{user: user}) do
    from(m in Memory,
      where: m.user_id == ^user.id,
      select:
        sum(
          fragment(
            "CASE WHEN ? = 'pending' THEN ? ELSE ? END",
            m.processing,
            m.original_bytes,
            m.stored_bytes
          )
        )
    )
    |> Repo.one()
    |> case do
      nil -> 0
      %Decimal{} = sum -> Decimal.to_integer(sum)
      sum -> sum
    end
    # Slideshow music counts too
    |> Kernel.+(Keepsakes.Music.bytes_used(user.id))
  end

  ## Media pipeline (internal, unscoped: called by Oban workers)

  @doc false
  def get_memory_for_processing(id), do: Repo.get(Memory, id)

  @doc false
  # Records the optimised result. EXIF month/year fill the date only when the
  # owner hasn't set any part of it, and the place only when empty, so typing
  # during processing always wins.
  def record_processed(%Memory{id: id}, result) do
    month = result[:month]
    year = result[:year]
    place = result[:place]

    {1, [memory]} =
      from(m in Memory,
        where: m.id == ^id,
        select: m,
        update: [
          set: [
            processing: "ready",
            processing_error: nil,
            stored_bytes: ^result.stored_bytes,
            width: ^result.width,
            height: ^result.height,
            taken_on: ^result[:taken_on],
            month:
              fragment(
                "CASE WHEN ? IS NULL AND ? IS NULL THEN ?::smallint ELSE ? END",
                m.month,
                m.year,
                type(^month, :integer),
                m.month
              ),
            year:
              fragment(
                "CASE WHEN ? IS NULL AND ? IS NULL THEN ?::smallint ELSE ? END",
                m.month,
                m.year,
                type(^year, :integer),
                m.year
              ),
            place: fragment("COALESCE(?, ?)", m.place, type(^place, :string)),
            updated_at: ^DateTime.utc_now()
          ]
        ]
      )
      |> Repo.update_all([])

    broadcast_memory_event(memory, :memory_updated)
    broadcast(memory.user_id, {:albums_changed, memory.user_id})
    {:ok, memory}
  end

  @doc false
  def record_failed(%Memory{} = memory, reason) do
    {:ok, memory} =
      memory
      |> Ecto.Changeset.change(
        processing: "failed",
        processing_error: String.slice(reason, 0, 250)
      )
      |> Repo.update()

    broadcast_memory_event(memory, :memory_updated)
    {:ok, memory}
  end

  defp broadcast_memory({:ok, memory} = result) do
    broadcast_memory_event(memory, :memory_updated)
    result
  end

  defp broadcast_memory(error), do: error
end
