defmodule Keepsakes.Billing.DiscountRedemption do
  @moduledoc """
  A user's use of a discount code, with its terms copied at the time. It
  takes a share off each invoice while active: not `ended_at`, and (for
  `repeating`) for periods starting before `ends_at`. A `once` discount
  ends as soon as its first invoice is paid.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "discount_redemptions" do
    field :percent_off, :integer
    field :duration, :string
    field :ends_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :discount_code, Keepsakes.Billing.DiscountCode
    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "Whether it still discounts a period starting at `period_start`."
  def applies?(%__MODULE__{ended_at: nil, ends_at: nil}, _period_start), do: true

  def applies?(%__MODULE__{ended_at: nil, ends_at: ends_at}, period_start),
    do: DateTime.before?(period_start, ends_at)

  def applies?(_redemption, _period_start), do: false
end
