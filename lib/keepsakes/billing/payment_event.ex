defmodule Keepsakes.Billing.PaymentEvent do
  @moduledoc """
  A webhook as the gateway sent it. The unique `(gateway, event_id)` index
  makes repeats harmless: a retried webhook is stored (and handled) once.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "payment_events" do
    field :gateway, :string
    field :event_id, :string
    field :event_type, :string
    field :payload, :map
    field :processed_at, :utc_datetime

    timestamps(updated_at: false)
  end
end
