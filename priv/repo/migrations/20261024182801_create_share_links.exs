defmodule Keepsakes.Repo.Migrations.CreateShareLinks do
  use Ecto.Migration

  def change do
    create table(:share_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :album_id, references(:albums, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # Public part of the URL: /a/<slug>
      add :slug, :string, null: false
      # The 6-digit access code, encrypted at rest (Cloak) so the owner can see it again
      add :code, :binary, null: false
      # auto | manual
      add :code_origin, :string, null: false, default: "auto"
      # Bumped on every code change; guest sessions remember the version they unlocked
      add :code_version, :integer, null: false, default: 1
      add :expires_at, :utc_datetime
      # timeline | autoscroll | slideshow
      add :default_view, :string, null: false, default: "timeline"
      add :show_details, :boolean, null: false, default: true
      add :allow_downloads, :boolean, null: false, default: false
      add :slideshow_music, :boolean, null: false, default: false
      add :open_count, :integer, null: false, default: 0
      add :last_opened_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:share_links, [:slug])
    # One link per album; turning sharing off deletes it
    create unique_index(:share_links, [:album_id])
    create index(:share_links, [:user_id])

    create constraint(:share_links, :code_origin_values,
             check: "code_origin IN ('auto', 'manual')"
           )

    create constraint(:share_links, :default_view_values,
             check: "default_view IN ('timeline', 'autoscroll', 'slideshow')"
           )
  end
end
