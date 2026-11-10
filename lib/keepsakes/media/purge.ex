defmodule Keepsakes.Media.Purge do
  @moduledoc """
  Oban job that deletes stored files after their memory is gone, so a
  delete in the UI never waits on storage round trips. Missing files are
  fine (`Storage.delete/1` treats them as deleted).
  """
  use Oban.Worker, queue: :media, max_attempts: 5

  alias Keepsakes.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"keys" => keys}}) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case Storage.delete(key) do
        :ok -> {:cont, :ok}
        {:error, :invalid_key} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
