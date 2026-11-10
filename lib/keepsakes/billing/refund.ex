defmodule Keepsakes.Billing.Refund do
  @moduledoc """
  Money given back on a successful payment by finance staff (see
  `Keepsakes.Finance.refund/4`), full or partial. `plan_action` is what
  happened to the customer's plan: `end_now` (moved to Free) or
  `end_at_period_end` (kept until the period ends, no renewal).

  `status` is `pending` from just before the gateway is asked until it
  answers, then `succeeded` or `failed` (with `failure_reason`). Only
  succeeded refunds count as money out; pending ones still hold back the
  refundable amount.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "refunds" do
    field :amount_minor, :integer
    field :currency, :string
    field :reason, :string
    field :plan_action, :string
    field :staff_email, :string
    field :status, :string, default: "pending"
    field :failure_reason, :string

    belongs_to :payment, Keepsakes.Billing.Payment
    belongs_to :invoice, Keepsakes.Billing.Invoice
    belongs_to :staff, Keepsakes.Accounts.User

    timestamps()
  end
end
