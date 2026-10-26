defmodule Keepsakes.Exports do
  @moduledoc """
  "Export everything": a zip of the owner's albums with each photo (the
  2400 px version) and an `album.json` per album holding titles, dates,
  captions, places and people.

  `request/1` queues `Keepsakes.Exports.ExportWorker`, which builds the zip
  in a temporary folder, stores it under the owner's storage prefix and
  emails a link. Exports can be downloaded for 7 days; the daily
  housekeeping job removes them after that.
  """
  import Ecto.Query

  alias Keepsakes.Accounts.{Scope, User, UserNotifier}
  alias Keepsakes.Albums.{Album, Memory}
  alias Keepsakes.Exports.{DataExport, ExportWorker}
  alias Keepsakes.{Repo, Storage}

  @keep_days 7

  @doc "Queues an export, or returns the one already being built."
  @spec request(Scope.t()) :: {:ok, DataExport.t()}
  def request(%Scope{user: user}) do
    case Repo.get_by(DataExport, user_id: user.id, status: "pending") do
      %DataExport{} = pending ->
        {:ok, pending}

      nil ->
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:export, %DataExport{user_id: user.id})
        |> Oban.insert(:job, &ExportWorker.new(%{export_id: &1.export.id}))
        |> Repo.transaction()
        |> case do
          {:ok, %{export: export}} -> {:ok, export}
        end
    end
  end

  @doc "The owner's most recent export, or nil."
  def latest(%Scope{user: user}) do
    Repo.one(
      from e in DataExport,
        where: e.user_id == ^user.id,
        order_by: [desc: e.inserted_at],
        limit: 1
    )
  end

  @doc "The owner's export with `id` if it can still be downloaded, else nil."
  def get_downloadable(%Scope{user: user}, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %DataExport{status: "ready"} = export <-
           Repo.get_by(DataExport, id: id, user_id: user.id),
         true <- DateTime.after?(export.expires_at, DateTime.utc_now()) do
      export
    else
      _ -> nil
    end
  end

  @doc false
  # ExportWorker: builds, stores and announces the zip
  def build(%DataExport{} = export) do
    user = Repo.get!(User, export.user_id)
    dir = Path.join(System.tmp_dir!(), "ks-export-#{export.id}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    try do
      files = Enum.flat_map(albums(user), &write_album(&1, dir))
      zip = Path.join(dir, "keepsake-export.zip")

      {:ok, _} =
        :zip.create(String.to_charlist(zip), Enum.map(files, &String.to_charlist/1),
          cwd: String.to_charlist(dir)
        )

      key = "users/#{user.id}/exports/#{export.id}.zip"
      :ok = Storage.put(key, {:file, zip}, content_type: "application/zip")

      export =
        export
        |> Ecto.Changeset.change(
          status: "ready",
          storage_key: key,
          bytes: File.stat!(zip).size,
          expires_at: DateTime.add(DateTime.utc_now(:second), @keep_days, :day)
        )
        |> Repo.update!()

      url = KeepsakesWeb.Endpoint.url() <> "/app/settings/privacy/exports/#{export.id}"
      UserNotifier.deliver_export_ready(user, url)
      broadcast(export)
      {:ok, export}
    after
      File.rm_rf!(dir)
    end
  end

  @doc false
  def mark_failed(%DataExport{} = export) do
    export = export |> Ecto.Changeset.change(status: "failed") |> Repo.update!()
    broadcast(export)
    export
  end

  @doc "Subscribes to `{:export_updated, export}` for the owner's exports."
  def subscribe(%Scope{user: user}),
    do: Phoenix.PubSub.subscribe(Keepsakes.PubSub, "user:#{user.id}:exports")

  defp broadcast(%DataExport{user_id: user_id} = export),
    do:
      Phoenix.PubSub.broadcast(
        Keepsakes.PubSub,
        "user:#{user_id}:exports",
        {:export_updated, export}
      )

  defp albums(user) do
    memories =
      from m in Memory,
        where: m.status == "published",
        order_by: [
          asc_nulls_last: m.year,
          asc_nulls_last: m.month,
          asc: m.position,
          asc: m.inserted_at
        ]

    from(a in Album,
      where: a.user_id == ^user.id,
      order_by: a.inserted_at,
      preload: [memories: ^memories]
    )
    |> Repo.all()
  end

  # Writes the album's photos and album.json; returns their paths relative to `dir`
  defp write_album(album, dir) do
    folder = unique_folder(dir, album.slug)
    File.mkdir_p!(Path.join(dir, folder))

    {entries, files} =
      album.memories
      |> Enum.with_index(1)
      |> Enum.map_reduce([], fn {memory, n}, files ->
        photo = photo_name(memory, n)
        path = Path.join(folder, photo)

        written =
          memory.processing == "ready" and
            match?({:ok, _}, fetch_to(Memory.variant_key(memory, 2400), Path.join(dir, path)))

        entry = %{
          title: memory.title,
          month: memory.month,
          year: memory.year,
          caption: memory.caption,
          place: memory.place,
          people: memory.people,
          photo: written && photo
        }

        {entry, if(written, do: [path | files], else: files)}
      end)

    meta = %{name: album.name, description: album.description, memories: entries}
    json = Path.join(folder, "album.json")
    File.write!(Path.join(dir, json), Jason.encode_to_iodata!(meta, pretty: true))
    [json | Enum.reverse(files)]
  end

  defp fetch_to(key, path) do
    with {:ok, data} <- Storage.get(key), do: {File.write(path, data), path}
  end

  defp unique_folder(dir, slug) do
    if File.exists?(Path.join(dir, slug)),
      do: "#{slug}-#{System.unique_integer([:positive])}",
      else: slug
  end

  # "003 First birthday.webp"
  defp photo_name(memory, n) do
    title =
      (memory.title || "photo")
      |> String.replace(~r/[^\p{L}\p{N} _-]/u, "")
      |> String.trim()
      |> String.slice(0, 60)

    "#{String.pad_leading(Integer.to_string(n), 3, "0")} #{if title == "", do: "photo", else: title}.webp"
  end

  @doc "Removes exports past their 7 days. Returns how many."
  def remove_expired(now \\ DateTime.utc_now(:second)) do
    from(e in DataExport, where: e.status == "ready" and e.expires_at <= ^now)
    |> Repo.all()
    |> Enum.count(fn export ->
      Storage.delete(export.storage_key)
      export |> Ecto.Changeset.change(status: "expired") |> Repo.update!()
    end)
  end
end
