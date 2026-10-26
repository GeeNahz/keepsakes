defmodule Keepsakes.Billing.Charge do
  @moduledoc """
  A payment as a gateway reports it, in our terms: amounts in minor units
  and `status` as `:successful`, `:pending` or `:failed`. `card` is set
  when the gateway returned a reusable card token.
  """

  @type card :: %{
          token: String.t(),
          brand: String.t() | nil,
          last4: String.t() | nil,
          expiry: String.t() | nil,
          email: String.t() | nil
        }

  @type t :: %__MODULE__{
          gateway_id: String.t() | nil,
          tx_ref: String.t() | nil,
          status: :successful | :pending | :failed,
          amount_minor: non_neg_integer() | nil,
          currency: String.t() | nil,
          card: card() | nil,
          message: String.t() | nil,
          raw: map()
        }

  defstruct [:gateway_id, :tx_ref, :status, :amount_minor, :currency, :card, :message, raw: %{}]
end
