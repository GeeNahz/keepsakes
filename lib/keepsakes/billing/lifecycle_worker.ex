defmodule Keepsakes.Billing.LifecycleWorker do
  @moduledoc "Hourly cron job: trial reminders, trial → grace, grace → Free (`Billing.advance/1`)."
  use Oban.Worker, queue: :billing, max_attempts: 3, unique: [period: 300]

  @impl true
  def perform(_job) do
    _counts = Keepsakes.Billing.advance()
    :ok
  end
end
