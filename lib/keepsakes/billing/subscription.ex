defmodule Keepsakes.Billing.Subscription do
  @moduledoc """
  A user's one current subscription.

  Statuses: `trialing` (on the trial plan until `trial_ends_at`), `grace`
  (trial or failed renewal over; full access until `grace_ends_at`),
  `active`, `past_due` (a renewal failed and is being retried) and
  `canceled`. When grace runs out the user moves to the Free plan as
  `active`.

  Paid plans run in periods (`current_period_start`/`_end`) and renew from
  the saved card at the end of each; `cancel_at_period_end` stops that and
  moves the user to Free when the period ends.
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
    field :retry_count, :integer, default: 0
    field :next_retry_at, :utc_datetime
    # The period end a renewal heads-up was sent for
    field :renewal_reminder_sent_for, :utc_datetime

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :plan, Keepsakes.Billing.Plan
    belongs_to :price, Keepsakes.Billing.Price
    # A downgrade or interval change that applies at the next renewal
    belongs_to :pending_price, Keepsakes.Billing.Price
    # The discount code in use, if any
    belongs_to :discount_redemption, Keepsakes.Billing.DiscountRedemption
    # A paid plan given by staff until current_period_end; never charged
    field :complimentary, :boolean, default: false

    timestamps()
  end
end
