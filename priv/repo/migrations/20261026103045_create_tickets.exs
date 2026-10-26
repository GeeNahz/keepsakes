defmodule Keepsakes.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    # Ticket numbers: KS-T-1001, KS-T-1002, ...
    execute "CREATE SEQUENCE ticket_number_seq START 1001", "DROP SEQUENCE ticket_number_seq"

    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :string, null: false
      # The owner who opened it; nil for a guest's album report
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      # Guest reports: an optional address to reply to, and what was reported
      add :reporter_email, :string
      add :album_id, references(:albums, type: :binary_id, on_delete: :nilify_all)
      add :share_link_id, references(:share_links, type: :binary_id, on_delete: :nilify_all)
      add :subject, :string, null: false
      # billing | technical | account | abuse | other
      add :category, :string, null: false
      # low | normal | high | urgent
      add :priority, :string, null: false, default: "normal"
      # open | awaiting_staff | awaiting_user | resolved | closed
      add :status, :string, null: false, default: "open"
      # Staff member handling it (Stage 7)
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # For response-time targets in the staff inbox
      add :first_response_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :last_activity_at, :utc_datetime, null: false
      # Satisfaction, once solved
      add :rating, :integer
      add :rating_comment, :string
      add :rated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tickets, [:number])
    create index(:tickets, [:user_id, :last_activity_at])
    create index(:tickets, [:status, :last_activity_at])

    create constraint(:tickets, :tickets_category,
             check: "category IN ('billing', 'technical', 'account', 'abuse', 'other')"
           )

    create constraint(:tickets, :tickets_priority,
             check: "priority IN ('low', 'normal', 'high', 'urgent')"
           )

    create constraint(:tickets, :tickets_status,
             check: "status IN ('open', 'awaiting_staff', 'awaiting_user', 'resolved', 'closed')"
           )

    create constraint(:tickets, :tickets_rating,
             check: "rating IS NULL OR rating BETWEEN 1 AND 5"
           )

    create table(:ticket_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      # user | staff | guest | system
      add :author_type, :string, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false
      # Staff-only notes, never shown to the customer
      add :internal, :boolean, null: false, default: false

      # Microseconds keep quick back-and-forth messages in order
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ticket_messages, [:ticket_id, :inserted_at])

    create table(:ticket_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:ticket_messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :storage_key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :bytes, :bigint, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ticket_attachments, [:message_id])
  end
end
