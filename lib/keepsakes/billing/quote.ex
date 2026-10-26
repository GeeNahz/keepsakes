defmodule Keepsakes.Billing.Quote do
  @moduledoc """
  What choosing a price means right now, shown before anyone pays:

    * `:checkout` - pay `amount_minor` today: the price, less
      `discount_minor` (a discount code, `discount_label`), less
      `credit_minor` for unused days of the current paid plan. The plan
      starts at once and runs until `period_end`, which includes any
      `free_months` earned through referrals. `discount_code` is set when
      the code is new (typed now) rather than one already in use.
    * `:scheduled` - nothing to pay now; the change applies at the next
      renewal (`starts_at`), e.g. a downgrade
  """

  @type t :: %__MODULE__{
          mode: :checkout | :scheduled,
          price: Keepsakes.Billing.Price.t(),
          subtotal_minor: non_neg_integer(),
          discount_minor: non_neg_integer(),
          discount_label: String.t() | nil,
          discount_code: Keepsakes.Billing.DiscountCode.t() | nil,
          credit_minor: non_neg_integer(),
          amount_minor: non_neg_integer(),
          free_months: non_neg_integer(),
          period_end: DateTime.t() | nil,
          starts_at: DateTime.t() | nil
        }

  defstruct [
    :mode,
    :price,
    :period_end,
    :starts_at,
    :discount_label,
    :discount_code,
    subtotal_minor: 0,
    discount_minor: 0,
    credit_minor: 0,
    amount_minor: 0,
    free_months: 0
  ]
end
