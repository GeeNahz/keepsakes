defmodule Keepsakes.Repo.Migrations.CreateStaffAndAudit do
  use Ecto.Migration

  # Permission keys are the catalogue in Keepsakes.Staff.Permissions; copied
  # here as data so the migration never depends on app code.
  @finance ~w(dashboard.view finance.view finance.refund finance.export)
  @support ~w(dashboard.view support.view support.reply support.assign users.view)

  @roles [
    %{
      key: "super_admin",
      name: "Super Admin",
      description: "Everything, including staff and roles. Can't be changed or removed.",
      system: true,
      # Super Admin holds every permission in code, so the list stays empty
      permissions: []
    },
    %{
      key: "finance",
      name: "Finance",
      description: "Payments, invoices, refunds and revenue.",
      system: false,
      permissions: @finance
    },
    %{
      key: "support",
      name: "Support",
      description: "The support inbox and customer details.",
      system: false,
      permissions: @support
    }
  ]

  def up do
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :name, :string, null: false
      add :description, :string
      # Super Admin: locked, holds every permission
      add :system, :boolean, null: false, default: false
      add :permissions, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:key])

    # A user with an active membership is staff (same account as customers)
    create table(:staff_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :active, :boolean, null: false, default: true
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:staff_memberships, [:user_id])

    create table(:staff_roles, primary_key: false) do
      add :membership_id,
          references(:staff_memberships, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:staff_roles, [:membership_id, :role_id])

    # Every admin change: who, what, on which record, before/after, from where
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # Kept even if the actor's account is later deleted
      add :actor_email, :string
      # e.g. "staff.granted", "role.updated", "user.suspended"
      add :action, :string, null: false
      add :target_type, :string
      add :target_id, :string
      add :target_label, :string
      add :changes, :map, null: false, default: %{}
      add :ip, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_events, [:inserted_at])
    create index(:audit_events, [:actor_id, :inserted_at])
    create index(:audit_events, [:target_type, :target_id])

    flush()

    now = DateTime.utc_now(:second)

    repo().insert_all(
      "roles",
      for role <- @roles do
        Map.merge(role, %{id: Ecto.UUID.bingenerate(), inserted_at: now, updated_at: now})
      end
    )
  end

  def down do
    drop table(:audit_events)
    drop table(:staff_roles)
    drop table(:staff_memberships)
    drop table(:roles)
  end
end
