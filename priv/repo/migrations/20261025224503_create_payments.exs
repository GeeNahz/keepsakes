defmodule Keepsakes.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    # Receipt numbers: KS-000001, KS-000002, ...
    execute "CREATE SEQUENCE invoice_number_seq", "DROP SEQUENCE invoice_number_seq"

    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :number, :string, null: false
      # checkout (new plan or upgrade) | renewal
      add :kind, :string, null: false
      add :plan_id, references(:plans, type: :binary_id), null: false
      add :price_id, references(:plan_prices, type: :binary_id), null: false
      add :currency, :string, null: false
      # Price, minus credit for unused days of the previous plan, = amount charged
      add :subtotal_minor, :bigint, null: false
      add :credit_minor, :bigint, null: false, default: 0
      add :amount_minor, :bigint, null: false
      # open | paid | void
      add :status, :string, null: false, default: "open"
      # Set when paid
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invoices, [:number])
    create index(:invoices, [:user_id, :inserted_at])
    create constraint(:invoices, :invoices_status, check: "status IN ('open', 'paid', 'void')")
    create constraint(:invoices, :invoices_kind, check: "kind IN ('checkout', 'renewal')")

    # One row per attempt to collect an invoice
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :gateway, :string, null: false
      # Our reference, sent to the gateway
      add :tx_ref, :string, null: false
      # The gateway's transaction ID, once known
      add :gateway_id, :string
      # pending | successful | failed
      add :status, :string, null: false, default: "pending"
      add :amount_minor, :bigint, null: false
      add :currency, :string, null: false
      add :failure_reason, :string
      # Last gateway response, for support
      add :raw, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payments, [:tx_ref])
    create index(:payments, [:status, :inserted_at])

    create constraint(:payments, :payments_status,
             check: "status IN ('pending', 'successful', 'failed')"
           )

    # The card renewals are charged to (one per user, replaced on each checkout)
    create table(:payment_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :gateway, :string, null: false
      # Card token, encrypted at rest (Cloak)
      add :token, :binary, null: false
      add :brand, :string
      add :last4, :string
      add :expiry, :string
      # Flutterwave binds the token to the email of the first charge
      add :email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payment_methods, [:user_id])

    # Webhooks as received, stored once each before any processing
    create table(:payment_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :gateway, :string, null: false
      add :event_id, :string, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :processed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:payment_events, [:gateway, :event_id])

    alter table(:subscriptions) do
      # Downgrade or interval change waiting for the next renewal
      add :pending_price_id, references(:plan_prices, type: :binary_id, on_delete: :nilify_all)
      # Failed renewals: how many retries so far, and when the next one runs
      add :retry_count, :integer, null: false, default: 0
      add :next_retry_at, :utc_datetime
    end

    create index(:subscriptions, [:status, :current_period_end])
    create index(:subscriptions, [:status, :next_retry_at])
  end
end
