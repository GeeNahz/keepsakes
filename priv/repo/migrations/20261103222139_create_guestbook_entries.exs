defmodule Keepsakes.Repo.Migrations.CreateGuestbookEntries do
  use Ecto.Migration

  def change do
    create table(:guestbook_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :album_id, references(:albums, type: :binary_id, on_delete: :delete_all), null: false
      # Kept when sharing is turned off, so approved notes survive
      add :share_link_id, references(:share_links, type: :binary_id, on_delete: :nilify_all)
      add :visitor_key, :string, null: false
      add :name, :string, null: false
      add :message, :text, null: false
      # "pending" until the owner or an editor approves it
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create index(:guestbook_entries, [:album_id, :status])
  end
end
