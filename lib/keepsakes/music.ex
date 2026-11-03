defmodule Keepsakes.Music do
  @moduledoc """
  Slideshow music: one track per album (`albums.music_track_id`), played
  to guests in the slideshow when the share link's `slideshow_music`
  switch is on.

  For now owners upload their own track (MP3 or M4A, at most
  #{div(15_000_000, 1_000_000)} MB). Uploading needs agreement to the
  current Terms of use, which make the owner responsible for having the
  rights. Tracks count toward the owner's storage.

  A built-in library would add `Keepsakes.Music.Track` rows with
  `source: "library"` and no owner, plus a picker that sets
  `music_track_id`; `url/1`, guests and storage need no change.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Albums
  alias Keepsakes.Albums.Album
  alias Keepsakes.Music.Track
  alias Keepsakes.{Entitlements, Flags, Repo, Storage}

  @max_bytes 15_000_000

  @doc "Largest track an owner may upload, in bytes."
  def max_bytes, do: @max_bytes

  @doc "Accepted file extensions, for the upload input."
  def accept, do: ~w(.mp3 .m4a)

  @doc "Bytes of uploaded tracks the owner has (for storage)."
  @spec bytes_used(Ecto.UUID.t()) :: non_neg_integer()
  def bytes_used(user_id) do
    from(t in Track, where: t.user_id == ^user_id, select: coalesce(sum(t.bytes), 0))
    |> Repo.one()
    |> case do
      %Decimal{} = sum -> Decimal.to_integer(sum)
      sum -> sum
    end
  end

  @doc """
  Whether the album's owner may use slideshow music: the `slideshow_music`
  flag is on for them and their plan includes it.
  """
  @spec available?(Scope.t()) :: :ok | :flag_off | :not_in_plan
  def available?(%Scope{user: user} = scope) do
    cond do
      not Flags.enabled?(:slideshow_music, user) -> :flag_off
      not Entitlements.can?(scope, :slideshow_music) -> :not_in_plan
      true -> :ok
    end
  end

  @doc "The album's track, or `nil`."
  @spec get_track(Album.t()) :: Track.t() | nil
  def get_track(%Album{music_track_id: nil}), do: nil
  def get_track(%Album{music_track_id: id}), do: Repo.get(Track, id)

  @doc "Signed URL for playing the track."
  def url(%Track{storage_key: key}), do: Storage.url(key)

  @doc """
  Sets the album's track from an uploaded file
  (`%{path: tmp, filename: "song.mp3", bytes: n}`), replacing any earlier
  one. `terms?` is the owner ticking the Terms of use agreement now; it's
  needed once per terms version.

  Errors: `:terms`, `:flag_off`, `:not_in_plan`, `:too_large`,
  `:not_audio`, or `{:over_limit, :storage_bytes, used, max}`.
  """
  @spec upload(Scope.t(), Album.t(), map(), boolean()) :: {:ok, Track.t()} | {:error, term()}
  def upload(%Scope{user: user} = scope, %Album{} = album, upload, terms? \\ false) do
    :ok = Albums.authorize!(scope, album, :manage)

    with :ok <- available?(scope),
         {:ok, user} <- terms(user, terms?),
         :ok <- if(upload.bytes > @max_bytes, do: {:error, :too_large}, else: :ok),
         {:ok, ext, content_type} <- sniff(upload.path) do
      store(%Scope{scope | user: user}, album, upload, ext, content_type)
    else
      :flag_off -> {:error, :flag_off}
      :not_in_plan -> {:error, :not_in_plan}
      error -> error
    end
  end

  defp terms(user, terms?) do
    cond do
      Accounts.terms_accepted?(user) -> {:ok, user}
      terms? -> Accounts.accept_terms(user)
      true -> {:error, :terms}
    end
  end

  defp store(%Scope{user: user} = scope, album, upload, ext, content_type) do
    id = Ecto.UUID.generate()
    key = "users/#{user.id}/music/#{id}#{ext}"

    with :ok <- Storage.put(key, {:file, upload.path}, content_type: content_type) do
      old = get_track(album)

      Multi.new()
      |> Multi.run(:limits, fn _repo, _ ->
        :ok = Entitlements.lock(scope)
        # The old track's bytes are freed by the swap
        used = Albums.storage_used(scope) - ((old && old.bytes) || 0)

        with :ok <- Entitlements.check(scope, :storage_bytes, used, upload.bytes),
             do: {:ok, :within}
      end)
      |> Multi.insert(:track, %Track{
        id: id,
        user_id: user.id,
        source: "upload",
        storage_key: key,
        filename: upload.filename |> Path.basename() |> String.slice(0, 200),
        content_type: content_type,
        bytes: upload.bytes
      })
      |> Multi.update(:album, fn %{track: track} ->
        Ecto.Changeset.change(album, music_track_id: track.id)
      end)
      |> Multi.run(:old, fn repo, _ -> delete_uploaded(repo, old) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{track: track}} ->
          if old, do: Storage.delete(old.storage_key)
          broadcast(user.id)
          {:ok, track}

        {:error, _step, reason, _} ->
          Storage.delete(key)
          {:error, reason}
      end
    end
  end

  @doc "Removes the album's music (an uploaded track's file goes too)."
  @spec remove(Scope.t(), Album.t()) :: {:ok, Album.t()}
  def remove(%Scope{} = scope, %Album{} = album) do
    :ok = Albums.authorize!(scope, album, :manage)
    old = get_track(album)

    {:ok, %{album: album}} =
      Multi.new()
      |> Multi.update(:album, Ecto.Changeset.change(album, music_track_id: nil))
      |> Multi.run(:old, fn repo, _ -> delete_uploaded(repo, old) end)
      |> Repo.transaction()

    if old && old.source == "upload", do: Storage.delete(old.storage_key)
    broadcast(album.user_id)
    {:ok, album}
  end

  # Library tracks are shared and never deleted with an album
  defp delete_uploaded(repo, %Track{source: "upload"} = track), do: repo.delete(track)
  defp delete_uploaded(_repo, _track), do: {:ok, nil}

  @doc false
  # Storage keys of the owner's uploaded tracks (account purge)
  def storage_keys(user_id),
    do: Repo.all(from t in Track, where: t.user_id == ^user_id, select: t.storage_key)

  @doc """
  Checks the file's first bytes: MP3 (an ID3 tag or an MPEG audio frame)
  or M4A (an MP4 `ftyp` box). Returns `{:ok, ext, content_type}`.
  """
  def sniff(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, <<"ID3", _::binary>>} ->
        {:ok, ".mp3", "audio/mpeg"}

      {:ok, <<0xFF, b, _::binary>>} when Bitwise.band(b, 0xE0) == 0xE0 ->
        {:ok, ".mp3", "audio/mpeg"}

      {:ok, <<_size::32, "ftyp", brand::binary-4, _::binary>>} ->
        m4a(brand)

      _ ->
        {:error, :not_audio}
    end
  end

  defp m4a(brand) when brand in ["M4A ", "M4B ", "mp42", "isom", "iso2", "mp41", "dash"],
    do: {:ok, ".m4a", "audio/mp4"}

  defp m4a(_brand), do: {:error, :not_audio}

  @doc "Friendly text for an upload error."
  def error_message(:terms), do: "Please agree to the Terms of use to add music."
  def error_message(:flag_off), do: "Slideshow music isn't available yet."
  def error_message(:not_in_plan), do: "Slideshow music isn't included in your plan."
  def error_message(:too_large), do: "Music files can be up to #{div(@max_bytes, 1_000_000)} MB."
  def error_message(:not_audio), do: "That doesn't look like an MP3 or M4A file."
  def error_message({:over_limit, _, _, _} = error), do: Entitlements.message(error)
  def error_message(_), do: "That music couldn't be added. Please try again."

  defp broadcast(user_id) do
    Phoenix.PubSub.broadcast(
      Keepsakes.PubSub,
      "user:#{user_id}:albums",
      {:albums_changed, user_id}
    )
  end
end
