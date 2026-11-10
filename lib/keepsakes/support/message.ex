defmodule Keepsakes.Support.Message do
  @moduledoc """
  One message on a ticket: from the customer (`user`), a guest reporter
  (`guest`), support (`staff`), or Keepsake itself (`system`, e.g. "marked
  as solved"). `internal` messages are staff notes, never shown to the
  customer.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "ticket_messages" do
    field :author_type, :string
    field :body, :string
    field :internal, :boolean, default: false

    belongs_to :ticket, Keepsakes.Support.Ticket
    belongs_to :author, Keepsakes.Accounts.User
    has_many :attachments, Keepsakes.Support.Attachment

    # Microseconds keep quick back-and-forth messages in order
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
