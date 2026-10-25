defmodule Keepsakes.Billing.Subscription do
  @moduledoc """
  A user's one current subscription.

  Statuses: `trialing` (on the trial plan until `trial_ends_at`), `grace`
  (trial or failed renewal over; full access until `grace_ends_at`),
  `active`, `past_due` (a renewal failed and is being retried) and
  `canceled`. When grace runs out the user moves to the Free plan as
  `active`.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "subscriptions" do
    field :status, :string
    field :trial_ends_at, :utc_datetime
    field :trial_reminder_sent_at, :utc_datetime
    field :grace_ends_at, :utc_datetime
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :plan, Keepsakes.Billing.Plan
    belongs_to :price, Keepsakes.Billing.Price

    timestamps()
  end
end
