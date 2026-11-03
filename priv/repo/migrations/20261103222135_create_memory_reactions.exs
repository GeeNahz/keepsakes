defmodule Keepsakes.Repo.Migrations.CreateMemoryReactions do
  use Ecto.Migration

  def change do
    # One heart per guest browser (visitor_key) per photo
    create table(:memory_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :memory_id, references(:memories, type: :binary_id, on_delete: :delete_all), null: false

      add :share_link_id, references(:share_links, type: :binary_id, on_delete: :delete_all),
        null: false

      add :visitor_key, :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:memory_reactions, [:memory_id, :visitor_key])
  end
end
