defmodule Keepsakes.Billing.Quote do
  @moduledoc """
  What choosing a price means right now, shown before anyone pays:

    * `:checkout` - pay `amount_minor` today (the price less `credit_minor`
      for unused days of the current paid plan); the plan starts at once
      and runs until `period_end`
    * `:scheduled` - nothing to pay now; the change applies at the next
      renewal (`starts_at`), e.g. a downgrade
  """

  @type t :: %__MODULE__{
          mode: :checkout | :scheduled,
          price: Keepsakes.Billing.Price.t(),
          subtotal_minor: non_neg_integer(),
          credit_minor: non_neg_integer(),
          amount_minor: non_neg_integer(),
          period_end: DateTime.t() | nil,
          starts_at: DateTime.t() | nil
        }

  defstruct [
    :mode,
    :price,
    :period_end,
    :starts_at,
    subtotal_minor: 0,
    credit_minor: 0,
    amount_minor: 0
  ]
end
