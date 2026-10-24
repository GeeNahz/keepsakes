defmodule Keepsakes.Repo.Migrations.CreateAlbumsAndMemories do
  use Ecto.Migration

  def change do
    create table(:albums, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    # Slugs are only unique per owner: /albums/<slug> is always scoped
    create unique_index(:albums, [:user_id, :slug])

    create table(:memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :album_id, references(:albums, type: :binary_id, on_delete: :delete_all), null: false
      # Denormalised owner for scoping and storage usage without a join
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # draft (still on the upload screen) | published
      add :status, :string, null: false, default: "draft"
      # pending | ready | failed (media pipeline)
      add :processing, :string, null: false, default: "pending"
      add :processing_error, :string
      add :title, :string
      add :month, :smallint
      add :year, :smallint
      add :caption, :text
      add :place, :string
      add :people, {:array, :string}, null: false, default: []
      add :position, :integer, null: false, default: 0
      add :storage_prefix, :string, null: false
      add :original_filename, :string
      add :original_bytes, :bigint, null: false, default: 0
      add :stored_bytes, :bigint, null: false, default: 0
      add :width, :integer
      add :height, :integer
      add :taken_on, :date

      # Microseconds: photos uploaded together must keep their upload order
      timestamps(type: :utc_datetime_usec)
    end

    create index(:memories, [:album_id, :status])
    create index(:memories, [:user_id])

    create constraint(:memories, :month_range, check: "month BETWEEN 1 AND 12")
    create constraint(:memories, :status_values, check: "status IN ('draft', 'published')")

    create constraint(:memories, :processing_values,
             check: "processing IN ('pending', 'ready', 'failed')"
           )

    # Added after memories exists; clearing the cover never deletes the album
    alter table(:albums) do
      add :cover_memory_id, references(:memories, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
