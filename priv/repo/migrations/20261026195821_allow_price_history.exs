defmodule Keepsakes.Repo.Migrations.AllowPriceHistory do
  use Ecto.Migration

  # A changed price is a new row; the old one stays (inactive) for the
  # subscribers still paying it. Only one active price per slot.
  def change do
    drop unique_index(:plan_prices, [:plan_id, :currency, :interval])

    create unique_index(:plan_prices, [:plan_id, :currency, :interval],
             where: "active",
             name: :plan_prices_one_active_per_slot
           )
  end
end
