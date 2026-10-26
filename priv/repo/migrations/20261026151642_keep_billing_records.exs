defmodule Keepsakes.Repo.Migrations.KeepBillingRecords do
  use Ecto.Migration

  # Invoices and payments are financial records: when an account is
  # deleted they stay, detached (user_id nil), with who they were for
  def change do
    alter table(:invoices) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: true,
        from: {references(:users, type: :binary_id, on_delete: :delete_all), null: false}

      add :billing_name, :string
      add :billing_email, :string
    end

    alter table(:payments) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: true,
        from: {references(:users, type: :binary_id, on_delete: :delete_all), null: false}
    end

    execute(
      """
      UPDATE invoices AS i
      SET billing_email = u.email,
          billing_name = trim(u.first_name || ' ' || coalesce(u.last_name, ''))
      FROM users AS u
      WHERE u.id = i.user_id
      """,
      ""
    )
  end
end
