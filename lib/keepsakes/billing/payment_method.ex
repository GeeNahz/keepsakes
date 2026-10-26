defmodule Keepsakes.Billing.PaymentMethod do
  @moduledoc """
  The card a user's renewals are charged to: the gateway's reusable token
  (encrypted at rest) and what we show ("Visa •••• 4242, 09/32").
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "payment_methods" do
    field :gateway, :string
    field :token, Keepsakes.Encrypted.Binary, redact: true
    field :brand, :string
    field :last4, :string
    field :expiry, :string
    field :email, :string

    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "`\"Visa •••• 4242 · expires 09/32\"`."
  def label(%__MODULE__{} = method) do
    brand = method.brand |> to_string() |> String.capitalize()
    expiry = if method.expiry, do: " · expires #{method.expiry}", else: ""
    String.trim("#{brand} •••• #{method.last4}#{expiry}")
  end
end
