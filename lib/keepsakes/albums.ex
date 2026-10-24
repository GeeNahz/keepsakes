defmodule Keepsakes.Albums do
  @moduledoc """
  Albums and their memories, always scoped to the owner in `%Scope{}`.

  Changes are broadcast on the owner's topic (see `subscribe/1`) so the
  sidebar, the album grid and the upload screen update live, including
  when the media pipeline finishes a photo:

    * `{:memory_updated, %Memory{}}`
    * `{:memory_deleted, %Memory{}}`
    * `{:albums_changed, user_id}`
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.Media.{ProcessMemory, Purge}
  alias Keepsakes.{Repo, Storage}

  ## PubSub

  @doc "Subscribes the caller to the owner's album and memory events."
  def subscribe(%Scope{user: user}),
    do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, topic(user.id))

  defp topic(user_id), do: "user:#{user_id}:albums"

  defp broadcast(user_id, message),
    do: Phoenix.PubSub.broadcast(Keepsakes.PubSub, topic(user_id), message)

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

  @spec change_album(Album.t(), map()) :: Ecto.Changeset.t()
  def change_album(%Album{} = album \\ %Album{}, attrs \\ %{}), do: Album.changeset(album, attrs)

  @doc "Creates an album for the owner with a slug unique among their albums."
  @spec create_album(Scope.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def create_album(%Scope{user: user}, attrs) do
    taken = Repo.all(from a in Album, where: a.user_id == ^user.id, select: a.slug)

    %Album{user_id: user.id}
    |> Album.changeset(attrs)
    |> Album.put_slug(taken)
    |> Ecto.Changeset.unique_constraint(:slug, name: :albums_user_id_slug_index)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> broadcast(user.id, {:albums_changed, user.id})
      _ -> :ok
    end)
  end

  @doc "Makes `memory` the album cover, or clears the cover with `nil`."
  @spec set_cover(Scope.t(), Album.t(), Memory.t() | nil) :: {:ok, Album.t()}
  def set_cover(%Scope{user: %{id: user_id} = user}, %Album{user_id: user_id} = album, memory) do
    album_id = album.id

    cover_id =
      case memory do
        %Memory{album_id: ^album_id, id: id} -> id
        nil -> nil
      end

    {:ok, album} = album |> Ecto.Changeset.change(cover_memory_id: cover_id) |> Repo.update()
    broadcast(user.id, {:albums_changed, user.id})
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

  defp album_memories(%Scope{user: user}, %Album{id: album_id}, status) do
    from m in Memory,
      where: m.user_id == ^user.id and m.album_id == ^album_id and m.status == ^status
  end

  @doc "The owner's memory with `id`. Raises `Ecto.NoResultsError` otherwise."
  @spec get_memory!(Scope.t(), Ecto.UUID.t()) :: Memory.t()
  def get_memory!(%Scope{user: user}, id) do
    Repo.one!(from m in Memory, where: m.user_id == ^user.id and m.id == ^id)
  end

  @doc """
  Stores an uploaded file as the original of a new draft memory and queues
  the media pipeline for it.

  `upload` is `%{path: tmp_path, filename: "IMG_2041.jpg", bytes: 6_800_000}`.
  """
  @spec create_draft(Scope.t(), Album.t(), map()) :: {:ok, Memory.t()} | {:error, term()}
  def create_draft(%Scope{user: %{id: user_id} = user}, %Album{user_id: user_id} = album, upload) do
    id = Ecto.UUID.generate()

    memory = %Memory{
      id: id,
      album_id: album.id,
      user_id: user.id,
      storage_prefix: "users/#{user.id}/albums/#{album.id}/memories/#{id}",
      original_filename: upload.filename |> Path.basename() |> String.slice(0, 255),
      original_bytes: upload.bytes
    }

    with :ok <- Storage.put(Memory.original_key(memory), {:file, upload.path}) do
      Multi.new()
      |> Multi.insert(:memory, memory)
      |> Oban.insert(:job, fn %{memory: memory} -> ProcessMemory.new(%{memory_id: memory.id}) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{memory: memory}} ->
          broadcast(user.id, {:memory_updated, memory})
          broadcast(user.id, {:albums_changed, user.id})
          {:ok, memory}

        {:error, _step, reason, _} ->
          Storage.delete(Memory.original_key(memory))
          {:error, reason}
      end
    end
  end

  @spec change_memory(Memory.t(), map()) :: Ecto.Changeset.t()
  def change_memory(%Memory{} = memory, attrs \\ %{}), do: Memory.changeset(memory, attrs)

  @doc "Saves the owner's edits to title, date, caption and place."
  @spec update_memory(Scope.t(), Memory.t(), map()) ::
          {:ok, Memory.t()} | {:error, Ecto.Changeset.t()}
  def update_memory(%Scope{user: %{id: user_id}}, %Memory{user_id: user_id} = memory, attrs) do
    memory |> Memory.changeset(attrs) |> Repo.update() |> broadcast_memory(user_id)
  end

  @doc "Replaces the people tagged in `memory`."
  @spec set_people(Scope.t(), Memory.t(), [String.t()]) ::
          {:ok, Memory.t()} | {:error, Ecto.Changeset.t()}
  def set_people(%Scope{user: %{id: user_id}}, %Memory{user_id: user_id} = memory, people) do
    memory |> Memory.people_changeset(people) |> Repo.update() |> broadcast_memory(user_id)
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

    broadcast(scope.user.id, {:albums_changed, scope.user.id})
    {:ok, count}
  end

  @doc "Deletes every draft in the album and their stored files."
  @spec discard_drafts(Scope.t(), Album.t()) :: {:ok, non_neg_integer()}
  def discard_drafts(%Scope{} = scope, %Album{} = album) do
    drafts = list_drafts(scope, album)
    Enum.each(drafts, &delete_memory(scope, &1))
    {:ok, length(drafts)}
  end

  @doc "Deletes a memory; its files are removed in the background."
  @spec delete_memory(Scope.t(), Memory.t()) :: {:ok, Memory.t()} | {:error, term()}
  def delete_memory(%Scope{user: %{id: user_id} = user}, %Memory{user_id: user_id} = memory) do
    Multi.new()
    |> Multi.delete(:memory, memory)
    |> Oban.insert(:purge, Purge.new(%{keys: Memory.all_keys(memory)}))
    |> Repo.transaction()
    |> case do
      {:ok, %{memory: deleted}} ->
        broadcast(user.id, {:memory_deleted, deleted})
        broadcast(user.id, {:albums_changed, user.id})
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

    broadcast(memory.user_id, {:memory_updated, memory})
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

    broadcast(memory.user_id, {:memory_updated, memory})
    {:ok, memory}
  end

  defp broadcast_memory({:ok, memory} = result, user_id) do
    broadcast(user_id, {:memory_updated, memory})
    result
  end

  defp broadcast_memory(error, _user_id), do: error
end
