defmodule Keepsakes.Repo.Migrations.CreateRefunds do
  use Ecto.Migration

  def change do
    # Money given back on a payment by finance staff (full or partial)
    create table(:refunds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_id, references(:payments, type: :binary_id, on_delete: :restrict), null: false
      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :restrict), null: false
      add :amount_minor, :bigint, null: false
      add :currency, :string, null: false
      add :reason, :string, null: false
      # end_now | end_at_period_end
      add :plan_action, :string, null: false
      add :staff_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :staff_email, :string, null: false
      # Saved as pending before the gateway is asked, so a refund the gateway
      # made is never lost: pending -> succeeded | failed
      add :status, :string, null: false, default: "pending"
      add :failure_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:refunds, [:payment_id])
    create index(:refunds, [:inserted_at])
    create constraint(:refunds, :refunds_amount_positive, check: "amount_minor > 0")

    create constraint(:refunds, :refunds_status,
             check: "status IN ('pending', 'succeeded', 'failed')"
           )

    create constraint(:refunds, :refunds_plan_action,
             check: "plan_action IN ('end_now', 'end_at_period_end')"
           )
  end
end
