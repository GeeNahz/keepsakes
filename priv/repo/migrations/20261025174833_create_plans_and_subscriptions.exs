defmodule Keepsakes.Repo.Migrations.CreatePlansAndSubscriptions do
  use Ecto.Migration

  @gb 1024 * 1024 * 1024

  # Feature keys are the catalogue in Keepsakes.Billing.Features; nil limits
  # mean unlimited. Copied here as data so the migration never depends on
  # app code that may change later.
  @free %{
    "max_albums" => 2,
    "max_memories_per_album" => 100,
    "storage_bytes" => @gb,
    "max_upload_mb" => 10,
    "collaborator_seats" => 0,
    "custom_domains" => 0,
    "premium_templates" => false,
    "guest_downloads" => false,
    "remove_branding" => false,
    "guest_uploads" => false,
    "time_capsule" => false,
    "reactions_guestbook" => false,
    "slideshow_music" => false
  }

  @plus %{
    "max_albums" => 10,
    "max_memories_per_album" => 500,
    "storage_bytes" => 20 * @gb,
    "max_upload_mb" => 25,
    "collaborator_seats" => 2,
    "custom_domains" => 0,
    "premium_templates" => true,
    "guest_downloads" => true,
    "remove_branding" => true,
    "guest_uploads" => true,
    "time_capsule" => true,
    "reactions_guestbook" => true,
    "slideshow_music" => true
  }

  @pro %{
    "max_albums" => nil,
    "max_memories_per_album" => nil,
    "storage_bytes" => 100 * @gb,
    "max_upload_mb" => 25,
    "collaborator_seats" => 5,
    "custom_domains" => 1,
    "premium_templates" => true,
    "guest_downloads" => true,
    "remove_branding" => true,
    "guest_uploads" => true,
    "time_capsule" => true,
    "reactions_guestbook" => true,
    "slideshow_music" => true
  }

  @plans [
    %{
      slug: "free",
      name: "Free",
      description: "For a first album and trying things out.",
      kind: "free",
      public: true,
      position: 1,
      features: @free
    },
    %{
      slug: "plus",
      name: "Plus",
      description: "For a growing family album, with premium templates.",
      kind: "paid",
      public: true,
      position: 2,
      features: @plus
    },
    %{
      slug: "pro",
      name: "Pro",
      description: "Unlimited albums, more storage and your own domain.",
      kind: "paid",
      public: true,
      position: 3,
      features: @pro
    },
    # Every new account starts here: Pro features for Settings.trial_days
    %{
      slug: "trial",
      name: "Free trial",
      description: "Everything in Pro while you try Keepsake.",
      kind: "trial",
      public: false,
      position: 0,
      features: @pro
    }
  ]

  # [TBD] Placeholder prices, in minor units (kobo / cents). Change them
  # before going live (admin portal, Stage 7).
  @prices [
    {"plus", "NGN", "month", 500_000},
    {"plus", "NGN", "year", 5_000_000},
    {"plus", "USD", "month", 500},
    {"plus", "USD", "year", 5_000},
    {"pro", "NGN", "month", 1_200_000},
    {"pro", "NGN", "year", 12_000_000},
    {"pro", "USD", "month", 1_200},
    {"pro", "USD", "year", 12_000}
  ]

  def up do
    create table(:plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      # free | trial | paid
      add :kind, :string, null: false
      # Shown on the pricing page and plan picker
      add :public, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      # feature key => limit (nil = unlimited) or true/false
      add :features, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plans, [:slug])
    create constraint(:plans, :plans_kind, check: "kind IN ('free', 'trial', 'paid')")

    create table(:plan_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plan_id, references(:plans, type: :binary_id, on_delete: :delete_all), null: false
      # NGN | USD
      add :currency, :string, null: false
      # month | year
      add :interval, :string, null: false
      # Kobo or cents
      add :amount_minor, :bigint, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plan_prices, [:plan_id, :currency, :interval])

    create constraint(:plan_prices, :plan_prices_currency, check: "currency IN ('NGN', 'USD')")
    create constraint(:plan_prices, :plan_prices_interval, check: "interval IN ('month', 'year')")
    create constraint(:plan_prices, :plan_prices_amount, check: "amount_minor > 0")

    # One current subscription per user
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, type: :binary_id), null: false
      # The price being paid (paid plans only)
      add :price_id, references(:plan_prices, type: :binary_id, on_delete: :nilify_all)
      # trialing | grace | active | past_due | canceled
      add :status, :string, null: false
      add :trial_ends_at, :utc_datetime
      add :trial_reminder_sent_at, :utc_datetime
      add :grace_ends_at, :utc_datetime
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :cancel_at_period_end, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:user_id])
    create index(:subscriptions, [:status, :trial_ends_at])
    create index(:subscriptions, [:status, :grace_ends_at])

    create constraint(:subscriptions, :subscriptions_status,
             check: "status IN ('trialing', 'grace', 'active', 'past_due', 'canceled')"
           )

    # Every plan or status change, for support and the admin portal
    create table(:subscription_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :delete_all),
        null: false

      # e.g. trial_started, trial_reminder, grace_started, moved_to_free
      add :kind, :string, null: false
      add :from_status, :string
      add :to_status, :string
      add :from_plan, :string
      add :to_plan, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:subscription_events, [:subscription_id, :inserted_at])

    flush()

    now = DateTime.utc_now(:second)

    plan_ids =
      for plan <- @plans, into: %{} do
        id = Ecto.UUID.bingenerate()

        repo().insert_all("plans", [
          Map.merge(plan, %{id: id, inserted_at: now, updated_at: now})
        ])

        {plan.slug, id}
      end

    repo().insert_all(
      "plan_prices",
      for {slug, currency, interval, amount} <- @prices do
        %{
          id: Ecto.UUID.bingenerate(),
          plan_id: plan_ids[slug],
          currency: currency,
          interval: interval,
          amount_minor: amount,
          inserted_at: now,
          updated_at: now
        }
      end
    )

    # Existing accounts start their trial today
    execute """
    INSERT INTO subscriptions (id, user_id, plan_id, status, trial_ends_at, inserted_at, updated_at)
    SELECT gen_random_uuid(), u.id, p.id, 'trialing', now() + interval '60 days', now(), now()
    FROM users u, plans p
    WHERE p.slug = 'trial'
    """

    # Daylight becomes the first premium template
    execute "UPDATE templates SET premium = true WHERE slug = 'daylight'"
  end

  def down do
    execute "UPDATE templates SET premium = false WHERE slug = 'daylight'"
    drop table(:subscription_events)
    drop table(:subscriptions)
    drop table(:plan_prices)
    drop table(:plans)
  end
end
