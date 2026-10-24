defmodule Keepsakes.Media do
  @moduledoc """
  Image pipeline (libvips via `Image`): read the photo's EXIF, rotate it
  upright, and produce the stored WebP variants with **all metadata
  stripped** (camera, date and GPS never reach guests).

  Variants are keyed by nominal width (see `Keepsakes.Albums.Memory.variants/0`);
  each fits its longest side within that many pixels and is never
  upscaled. The largest uses `Settings.image_long_edge` (2400 by default).
  """
  alias Keepsakes.Albums.Memory
  alias Keepsakes.Settings

  @type result :: %{
          variants: %{pos_integer() => binary()},
          width: pos_integer(),
          height: pos_integer(),
          taken_on: Date.t() | nil,
          gps: {float(), float()} | nil
        }

  @doc """
  Decodes `binary` (JPEG, PNG, HEIC/HEIF or WebP) and returns the optimised
  variants plus what EXIF says about when and where it was taken.

  Options: `:long_edge` and `:quality` (default from `Keepsakes.Settings`).
  """
  @spec optimise(binary(), keyword()) :: {:ok, result} | {:error, term()}
  def optimise(binary, opts \\ []) do
    long_edge = Keyword.get_lazy(opts, :long_edge, fn -> Settings.get(:image_long_edge) end)
    quality = Keyword.get_lazy(opts, :quality, fn -> Settings.get(:image_quality) end)
    largest = Memory.variants() |> List.last()

    with {:ok, image} <- Image.from_binary(binary),
         exif = read_exif(image),
         {:ok, {upright, _flags}} <- Image.autorotate(image),
         {:ok, variants} <- build_variants(upright, largest, long_edge, quality) do
      {main_width, main_height} = dimensions(variants[largest])

      {:ok,
       %{
         variants: variants,
         width: main_width,
         height: main_height,
         taken_on: taken_on(exif),
         gps: gps(exif)
       }}
    end
  end

  defp build_variants(image, largest, long_edge, quality) do
    Enum.reduce_while(Memory.variants(), {:ok, %{}}, fn width, {:ok, acc} ->
      length = if width == largest, do: long_edge, else: min(width, long_edge)

      with {:ok, resized} <- Image.thumbnail(image, length, resize: :down),
           {:ok, webp} <-
             Image.write(resized, :memory,
               suffix: ".webp",
               quality: quality,
               strip_metadata: true
             ) do
        {:cont, {:ok, Map.put(acc, width, webp)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp dimensions(webp) do
    {:ok, image} = Image.from_binary(webp)
    {Image.width(image), Image.height(image)}
  end

  defp read_exif(image) do
    case Image.exif(image) do
      {:ok, exif} -> exif
      {:error, _} -> %{}
    end
  end

  @doc false
  def taken_on(%{exif: %{datetime_original: %NaiveDateTime{} = taken}}),
    do: NaiveDateTime.to_date(taken)

  def taken_on(_exif), do: nil

  @doc false
  # Degrees/minutes/seconds plus N/S/E/W refs to signed decimal degrees.
  def gps(%{gps: %{gps_latitude: [_, _, _] = lat, gps_longitude: [_, _, _] = lon} = gps}) do
    with {:ok, lat} <- to_decimal(lat, gps.gps_latitude_ref, "S"),
         {:ok, lon} <- to_decimal(lon, gps.gps_longitude_ref, "W"),
         true <- abs(lat) <= 90 and abs(lon) <= 180,
         false <- lat == 0.0 and lon == 0.0 do
      {lat, lon}
    else
      _ -> nil
    end
  end

  def gps(_exif), do: nil

  defp to_decimal([d, m, s], ref, negative_ref)
       when is_number(d) and is_number(m) and is_number(s) do
    value = d + m / 60 + s / 3600
    {:ok, if(trim_ref(ref) == negative_ref, do: -value, else: value)}
  end

  defp to_decimal(_dms, _ref, _negative_ref), do: :error

  defp trim_ref(ref) when is_binary(ref),
    do: ref |> String.trim_trailing("\x00") |> String.upcase()

  defp trim_ref(_), do: nil
end
