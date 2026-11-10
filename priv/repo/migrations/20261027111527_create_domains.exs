defmodule Keepsakes.Repo.Migrations.CreateDomains do
  use Ecto.Migration

  def change do
    # A customer's own web address for their public site (Keepsakes.Domains)
    create table(:domains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :hostname, :string, null: false
      # pending | verified | failed | blocked
      add :status, :string, null: false, default: "pending"
      # Goes in the TXT record _keepsake.<hostname> to prove ownership
      add :verification_token, :string, null: false
      add :verified_at, :utc_datetime
      add :last_checked_at, :utc_datetime
      # Checks since the last change of status (drives the polling schedule)
      add :checks, :integer, null: false, default: 0
      add :last_error, :string
      add :blocked_reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:domains, [:hostname])
    create index(:domains, [:user_id])
    create index(:domains, [:status, :last_checked_at])

    create constraint(:domains, :domains_status,
             check: "status IN ('pending', 'verified', 'failed', 'blocked')"
           )

    # Names staff never allow, exact ("bad.example") or wildcard ("*.bad.example")
    create table(:blocked_hostnames, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pattern, :string, null: false
      add :reason, :string, null: false
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:blocked_hostnames, [:pattern])

    alter table(:albums) do
      # Listed on the owner's public site (their custom domain)
      add :show_on_site, :boolean, null: false, default: false
    end
  end
end
