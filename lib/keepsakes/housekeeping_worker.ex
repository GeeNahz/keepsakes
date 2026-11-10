defmodule Keepsakes.HousekeepingWorker do
  @moduledoc """
  Daily cron job (07:15 Lagos time): the guest-activity emails, removing
  data exports past their 7 days, closing tickets solved 7 days ago, and
  deleting accounts whose 14-day pause has run out.
  """
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  @impl true
  def perform(_job) do
    Keepsakes.Sharing.send_guest_digests()
    Keepsakes.Exports.remove_expired()
    Keepsakes.Support.close_resolved()
    Keepsakes.Accounts.purge_deleted()
    :ok
  end
end
