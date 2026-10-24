defmodule Keepsakes.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  # ErrorTracker manages its own tables and versions.
  def up, do: ErrorTracker.Migration.up(version: 5)

  def down, do: ErrorTracker.Migration.down(version: 1)
end
