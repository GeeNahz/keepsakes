defmodule Keepsakes.AlbumsFixtures do
  @moduledoc """
  Albums, memories and generated test photos (no image files are checked
  into the repo; photos are drawn with libvips on the fly).
  """
  alias Keepsakes.Albums

  def album_fixture(scope, attrs \\ %{}) do
    {:ok, album} =
      Albums.create_album(
        scope,
        Enum.into(attrs, %{name: "Album #{System.unique_integer([:positive])}"})
      )

    album
  end

  @doc """
  A draft memory whose original is `jpeg/1` written to a temp file.
  Processing is queued but, with Oban in manual mode, not run.
  """
  def draft_fixture(scope, album, opts \\ []) do
    binary = Keyword.get_lazy(opts, :binary, fn -> jpeg(opts) end)
    path = Path.join(System.tmp_dir!(), "ks-upload-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, binary)

    {:ok, memory} =
      Albums.create_draft(scope, album, %{
        path: path,
        filename: Keyword.get(opts, :filename, "IMG_0001.jpg"),
        bytes: byte_size(binary)
      })

    File.rm(path)
    memory
  end

  @doc "A published memory with the given form attrs (title/month/year...)."
  def memory_fixture(scope, album, attrs \\ %{}) do
    memory = draft_fixture(scope, album)
    {:ok, memory} = Albums.update_memory(scope, memory, Enum.into(attrs, %{}))
    {:ok, _} = Albums.publish_drafts(scope, album)
    Albums.get_memory!(scope, memory.id)
  end

  @doc """
  JPEG bytes, optionally with EXIF.

  Options: `:width` (1200), `:height` (800), `:taken` ("2019:04:12 10:00:00"
  style string) and `:gps` (`{lat, lon}` in decimal degrees).
  """
  def jpeg(opts \\ []) do
    {:ok, image} =
      Image.new(Keyword.get(opts, :width, 1200), Keyword.get(opts, :height, 800),
        color: [200, 120, 80]
      )

    {:ok, image} =
      Vix.Vips.Image.mutate(image, fn mut ->
        if taken = opts[:taken], do: set_exif(mut, "exif-ifd2-DateTimeOriginal", taken)

        case opts[:gps] do
          {lat, lon} ->
            set_exif(mut, "exif-ifd3-GPSLatitude", dms(lat))
            set_exif(mut, "exif-ifd3-GPSLatitudeRef", if(lat < 0, do: "S", else: "N"))
            set_exif(mut, "exif-ifd3-GPSLongitude", dms(lon))
            set_exif(mut, "exif-ifd3-GPSLongitudeRef", if(lon < 0, do: "W", else: "E"))

          nil ->
            :ok
        end

        :ok
      end)

    {:ok, binary} = Vix.Vips.Image.write_to_buffer(image, ".jpg")
    binary
  end

  defp set_exif(mut, name, value),
    do: :ok = Vix.Vips.MutableImage.set(mut, name, :gchararray, value)

  # libvips takes rationals as "num/den num/den num/den"
  defp dms(decimal) do
    value = abs(decimal)
    degrees = trunc(value)
    minutes = trunc((value - degrees) * 60)
    seconds = round(((value - degrees) * 60 - minutes) * 60 * 100)
    "#{degrees}/1 #{minutes}/1 #{seconds}/100"
  end
end
