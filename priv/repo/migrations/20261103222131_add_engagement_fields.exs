defmodule Keepsakes.Repo.Migrations.AddEngagementFields do
  use Ecto.Migration

  def change do
    # Guest photos wait as "submitted" until approved
    drop constraint(:memories, :status_values, check: "status IN ('draft', 'published')")

    create constraint(:memories, :status_values,
             check: "status IN ('draft', 'published', 'submitted')"
           )

    alter table(:memories) do
      # "owner" or "guest" (added through the album's guest upload page)
      add :source, :string, null: false, default: "owner"
      add :guest_name, :string
      # Guests confirm they have the right to share the photo
      add :rights_confirmed_at, :utc_datetime
      # Time capsule: hidden from guests until then
      add :reveal_at, :utc_datetime
    end

    alter table(:albums) do
      add :reveal_at, :utc_datetime
    end

    alter table(:share_links) do
      add :guest_uploads, :boolean, null: false, default: false
      add :reactions_guestbook, :boolean, null: false, default: false
    end

    create constraint(:memories, :source_values, check: "source IN ('owner', 'guest')")
  end
end
