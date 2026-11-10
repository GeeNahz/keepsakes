defmodule Keepsakes.Billing.Payment do
  @moduledoc """
  One attempt to collect an invoice through the gateway, identified by our
  `tx_ref`. A failed renewal that is retried gets a new payment on the
  same invoice.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "payments" do
    field :gateway, :string
    field :tx_ref, :string
    field :gateway_id, :string
    field :status, :string, default: "pending"
    field :amount_minor, :integer
    field :currency, :string
    field :failure_reason, :string
    field :raw, :map

    belongs_to :invoice, Keepsakes.Billing.Invoice
    belongs_to :user, Keepsakes.Accounts.User
    has_many :refunds, Keepsakes.Billing.Refund

    timestamps()
  end
end
