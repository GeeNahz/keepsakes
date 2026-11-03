defmodule Keepsakes.Repo.Migrations.CreateMusicTracks do
  use Ecto.Migration

  def change do
    # Slideshow music. "upload" tracks belong to an owner; a built-in
    # library later adds "library" rows with no user_id.
    create table(:music_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :source, :string, null: false, default: "upload"
      add :storage_key, :string, null: false
      add :filename, :string
      add :content_type, :string, null: false
      add :bytes, :bigint, null: false, default: 0
      add :title, :string
      add :duration_seconds, :integer

      timestamps()
    end

    create index(:music_tracks, [:user_id])

    alter table(:albums) do
      add :music_track_id, references(:music_tracks, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
