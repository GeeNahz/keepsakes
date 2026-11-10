defmodule Keepsakes.Repo.Migrations.AddSettingsFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Profile
      add :bio, :string

      # Two-step login: authenticator secret (encrypted, Cloak), when it was
      # turned on, and hashed single-use recovery codes
      add :totp_secret, :binary
      add :totp_enabled_at, :utc_datetime
      add :recovery_codes, {:array, :string}, null: false, default: []

      # Email preferences (receipts, payment problems and security emails
      # always send)
      add :notify_product_news, :boolean, null: false, default: false
      add :notify_guest_activity, :boolean, null: false, default: true
      add :notify_billing_reminders, :boolean, null: false, default: true

      # Sharing defaults for new share links
      add :share_code_mode, :string, null: false, default: "auto"
      add :share_expires_in, :string, null: false, default: "never"
      add :share_default_view, :string, null: false, default: "timeline"
      add :share_show_details, :boolean, null: false, default: true
      add :share_allow_downloads, :boolean, null: false, default: false

      # Paused for deletion; everything is removed 14 days after this
      add :deletion_requested_at, :utc_datetime
    end

    create index(:users, [:deletion_requested_at])

    # Shown in Security -> signed-in devices
    alter table(:users_tokens) do
      add :user_agent, :string
      add :ip, :string
    end

    # Visits since the last guest-activity email
    alter table(:share_links) do
      add :opens_since_digest, :integer, null: false, default: 0
    end

    # The period end a renewal heads-up email was last sent for
    alter table(:subscriptions) do
      add :renewal_reminder_sent_for, :utc_datetime
    end

    # "Export everything" zips, kept for 7 days
    create table(:data_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # pending | ready | failed
      add :status, :string, null: false, default: "pending"
      add :storage_key, :string
      add :bytes, :bigint
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:data_exports, [:user_id, :inserted_at])
    create index(:data_exports, [:status, :expires_at])
  end
end
