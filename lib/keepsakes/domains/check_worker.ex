defmodule Keepsakes.Domains.CheckWorker do
  @moduledoc "Every 10 minutes: checks the custom domains that are due (`Keepsakes.Domains.check_due/1`)."
  use Oban.Worker, queue: :domains, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    Keepsakes.Domains.check_due()
    :ok
  end
end
