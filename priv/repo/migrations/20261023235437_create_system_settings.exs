defmodule Keepsakes.Repo.Migrations.CreateSystemSettings do
  use Ecto.Migration

  def change do
    create table(:system_settings) do
      add :key, :string, null: false
      add :value, :map, null: false
      # Staff member who last changed it; FK added once staff_users exists.
      add :updated_by_id, :binary_id

      timestamps()
    end

    create unique_index(:system_settings, [:key])
  end
end
