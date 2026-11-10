defmodule Keepsakes.Repo.Migrations.CreateCannedReplies do
  use Ecto.Migration

  def change do
    # Saved answers support staff can drop into a reply and edit
    create table(:canned_replies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:canned_replies, [:title])
  end
end
