defmodule Keepsakes.Exports.ExportWorker do
  @moduledoc "Builds one data export (`Keepsakes.Exports.build/1`)."
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Keepsakes.Exports
  alias Keepsakes.Exports.DataExport
  alias Keepsakes.Repo

  @impl true
  def perform(%Oban.Job{args: %{"export_id" => id}, attempt: attempt, max_attempts: max}) do
    case Repo.get(DataExport, id) do
      %DataExport{status: "pending"} = export ->
        try do
          {:ok, _} = Exports.build(export)
          :ok
        rescue
          error ->
            if attempt >= max, do: Exports.mark_failed(export)
            reraise error, __STACKTRACE__
        end

      _ ->
        :ok
    end
  end
end
