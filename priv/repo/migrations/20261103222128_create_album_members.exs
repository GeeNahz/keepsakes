defmodule Keepsakes.Repo.Migrations.CreateAlbumMembers do
  use Ecto.Migration

  def change do
    create table(:album_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :album_id, references(:albums, type: :binary_id, on_delete: :delete_all), null: false
      # Set when the invitation is accepted
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token_hash, :binary
      add :invited_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps()
    end

    create unique_index(:album_members, [:album_id, :email])
    create unique_index(:album_members, [:token_hash])
    create index(:album_members, [:user_id])
  end
end
