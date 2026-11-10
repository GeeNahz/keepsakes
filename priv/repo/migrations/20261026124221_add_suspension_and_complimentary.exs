defmodule Keepsakes.Repo.Migrations.AddSuspensionAndComplimentary do
  use Ecto.Migration

  def change do
    # Set by staff: the account can't sign in and its shared links stop
    alter table(:users) do
      add :suspended_at, :utc_datetime
      add :suspension_reason, :string
    end

    # A paid plan given by staff until current_period_end, never charged
    alter table(:subscriptions) do
      add :complimentary, :boolean, null: false, default: false
    end
  end
end
