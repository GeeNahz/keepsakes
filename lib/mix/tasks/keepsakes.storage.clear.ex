defmodule Mix.Tasks.Keepsakes.Storage.Clear do
  @shortdoc "Deletes every object in the configured photo storage (dev only)"

  @moduledoc """
  Lists and deletes every object in the storage configured from the
  `S3_*` variables (or local disk when `S3_BUCKET` is empty). Use it with
  `mix ecto.reset` to start over with an empty bucket and database.

      $ mix keepsakes.storage.clear          # asks before deleting
      $ mix keepsakes.storage.clear --yes    # no prompt

  Refuses to run in `MIX_ENV=prod`, and refuses an S3 bucket whose name
  doesn't contain "staging", "dev" or "test" unless `--any-bucket` is given,
  so a `.env` pointing at the production bucket can't be wiped by accident.
  """
  use Mix.Task

  alias Keepsakes.Storage

  @requirements ["app.config"]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [yes: :boolean, any_bucket: :boolean])
    opts = Keyword.merge([yes: false, any_bucket: false], opts)
    shell = Mix.shell()

    if Mix.env() == :prod, do: Mix.raise("keepsakes.storage.clear never runs in prod")

    config = Application.fetch_env!(:keepsakes, Storage)
    bucket = config[:bucket]

    if config[:adapter] == Storage.S3 and not opts[:any_bucket] and
         not String.contains?(bucket, ["staging", "dev", "test"]) do
      Mix.raise("#{bucket} doesn't look like a dev bucket; pass --any-bucket to clear it anyway")
    end

    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, keys} = Storage.list()
    shell.info("#{length(keys)} object(s) in #{Storage.Check.describe()}")

    if keys != [] and (opts[:yes] || shell.yes?("Delete them all?")) do
      failed = Enum.reject(keys, &(Storage.delete(&1) == :ok))
      shell.info("Deleted #{length(keys) - length(failed)} object(s)")
      if failed != [], do: Mix.raise("Could not delete: #{Enum.join(failed, ", ")}")
    end
  end
end
