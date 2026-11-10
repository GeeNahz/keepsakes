defmodule Keepsakes.Media.ProcessMemory do
  @moduledoc """
  Oban job that optimises one uploaded photo:

  1. reads the original from storage
  2. `Keepsakes.Media.optimise/2`: EXIF date + GPS, upright, WebP variants
     with metadata stripped
  3. stores the variants, then records sizes and auto-filled month/year and
     place on the memory (never overwriting what the owner typed)
  4. deletes the original

  A photo that can't be decoded is marked `"failed"` straight away; storage
  or network errors are retried.
  """
  use Oban.Worker, queue: :media, max_attempts: 3, unique: [period: 300, keys: [:memory_id]]

  alias Keepsakes.{Albums, Media, Storage}
  alias Keepsakes.Albums.Memory
  alias Keepsakes.Media.Geocoder

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"memory_id" => id}} = job) do
    case Albums.get_memory_for_processing(id) do
      # Deleted (e.g. upload cancelled) before we got to it
      nil -> :ok
      %Memory{processing: "ready"} -> :ok
      memory -> process(memory, job)
    end
  end

  defp process(memory, job) do
    with {:ok, original} <- Storage.get(Memory.original_key(memory)),
         {:ok, result} <- optimise(original),
         :ok <- store_variants(memory, result.variants) do
      Albums.record_processed(memory, %{
        stored_bytes: result.variants |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum(),
        width: result.width,
        height: result.height,
        taken_on: result.taken_on,
        month: result.taken_on && result.taken_on.month,
        year: result.taken_on && result.taken_on.year,
        place: Geocoder.reverse(result.gps)
      })

      Storage.delete(Memory.original_key(memory))
      :ok
    else
      {:error, {:unreadable, reason}} ->
        Albums.record_failed(memory, "We couldn't read this photo (#{reason})")
        {:cancel, reason}

      {:error, :not_found} ->
        Albums.record_failed(memory, "The upload went missing. Please add it again.")
        {:cancel, :original_missing}

      {:error, _reason} = error ->
        if job.attempt >= job.max_attempts,
          do: Albums.record_failed(memory, "Optimising failed. Please try again.")

        error
    end
  end

  defp optimise(original) do
    case Media.optimise(original) do
      {:ok, result} -> {:ok, result}
      {:error, %{message: message}} -> {:error, {:unreadable, message}}
      {:error, reason} -> {:error, {:unreadable, inspect(reason)}}
    end
  end

  defp store_variants(memory, variants) do
    Enum.reduce_while(variants, :ok, fn {width, webp}, :ok ->
      case Storage.put(Memory.variant_key(memory, width), webp, content_type: "image/webp") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
