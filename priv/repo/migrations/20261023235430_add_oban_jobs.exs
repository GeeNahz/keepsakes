defmodule Keepsakes.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  # Oban manages its own tables (bigint job ids by design).
  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 1)
end
