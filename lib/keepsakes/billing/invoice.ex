defmodule Keepsakes.Billing.Invoice do
  @moduledoc """
  What a user owes for one period of a plan: the price, less any discount
  code, less any credit for unused days of the plan they're upgrading from. `open` until a
  payment succeeds (`paid`) or it's abandoned (`void`).
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "invoices" do
    field :number, :string
    field :kind, :string
    field :currency, :string
    field :subtotal_minor, :integer
    field :credit_minor, :integer, default: 0
    field :discount_minor, :integer, default: 0
    field :discount_label, :string
    field :amount_minor, :integer
    field :status, :string, default: "open"
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :paid_at, :utc_datetime
    # Who it was for, kept after the account is deleted (user_id goes nil)
    field :billing_name, :string
    field :billing_email, :string

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :subscription, Keepsakes.Billing.Subscription
    belongs_to :plan, Keepsakes.Billing.Plan
    belongs_to :price, Keepsakes.Billing.Price
    belongs_to :discount_code, Keepsakes.Billing.DiscountCode
    has_many :payments, Keepsakes.Billing.Payment
    has_many :refunds, Keepsakes.Billing.Refund

    timestamps()
  end
end
