defmodule Mix.Tasks.Keepsakes.Storage.Check do
  @shortdoc "Checks the configured photo storage end to end"

  @moduledoc """
  Writes, reads, signs a URL for, fetches and deletes a small test object
  using the storage configured from the `S3_*` variables (or local disk
  when `S3_BUCKET` is empty).

      $ mix keepsakes.storage.check

  Exits with status 1 when a step fails. In a release use
  `bin/keepsakes eval "Keepsakes.Release.storage_check()"`.
  """
  use Mix.Task

  # The endpoint must be running to sign local media URLs
  @requirements ["app.start"]

  @impl true
  def run(_args) do
    shell = Mix.shell()
    Keepsakes.Release.storage_check(&shell.info/1) || exit({:shutdown, 1})
  end
end
