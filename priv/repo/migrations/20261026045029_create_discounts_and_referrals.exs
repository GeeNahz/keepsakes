defmodule Keepsakes.Repo.Migrations.CreateDiscountsAndReferrals do
  use Ecto.Migration

  def change do
    create table(:discount_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Stored upper-case; matched case-insensitively
      add :code, :string, null: false
      add :description, :string
      add :percent_off, :integer, null: false
      # once (first payment) | repeating (duration_months) | forever
      add :duration, :string, null: false
      add :duration_months, :integer
      # nil = no cap
      add :max_redemptions, :integer
      add :redemptions_count, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      # Plan slugs the code works for; empty = every paid plan
      add :plan_slugs, {:array, :string}, null: false, default: []
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:discount_codes, [:code])

    create constraint(:discount_codes, :discount_codes_percent,
             check: "percent_off BETWEEN 1 AND 100"
           )

    create constraint(:discount_codes, :discount_codes_duration,
             check:
               "duration IN ('once', 'forever') OR (duration = 'repeating' AND duration_months > 0)"
           )

    # A user's use of a code: the discount applies to their invoices while
    # it's active (ended_at nil, and before ends_at when set)
    create table(:discount_redemptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :discount_code_id,
          references(:discount_codes, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # Copied from the code when redeemed, so later edits don't change it
      add :percent_off, :integer, null: false
      add :duration, :string, null: false
      add :ends_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Each user can use a code once
    create unique_index(:discount_redemptions, [:discount_code_id, :user_id])

    alter table(:subscriptions) do
      add :discount_redemption_id,
          references(:discount_redemptions, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:invoices) do
      add :discount_code_id, references(:discount_codes, type: :binary_id, on_delete: :nilify_all)
      add :discount_minor, :bigint, null: false, default: 0
      # "LAUNCH20 · 20% off", as shown on the receipt
      add :discount_label, :string
    end

    alter table(:users) do
      # Personal invite code: /auth/register?ref=<code>
      add :referral_code, :string
      add :referred_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # Set when this user's first payment earned their inviter a month
      add :referral_rewarded_at, :utc_datetime
      # Free months earned before paying, added to the first paid period
      add :free_months_banked, :integer, null: false, default: 0
    end

    execute(
      "UPDATE users SET referral_code = upper(substr(md5(random()::text || id::text), 1, 8))",
      ""
    )

    create unique_index(:users, [:referral_code])
    create index(:users, [:referred_by_id])
  end
end
