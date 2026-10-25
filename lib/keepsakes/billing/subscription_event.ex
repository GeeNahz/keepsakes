defmodule Keepsakes.Billing.SubscriptionEvent do
  @moduledoc "One change to a subscription (plan, status or a reminder sent)."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "subscription_events" do
    field :kind, :string
    field :from_status, :string
    field :to_status, :string
    field :from_plan, :string
    field :to_plan, :string

    belongs_to :subscription, Keepsakes.Billing.Subscription

    timestamps(updated_at: false)
  end
end
