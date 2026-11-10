defmodule Keepsakes.Support.Attachment do
  @moduledoc "A photo or PDF attached to a ticket message (stored privately)."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "ticket_attachments" do
    field :storage_key, :string
    field :filename, :string
    field :content_type, :string
    field :bytes, :integer

    belongs_to :message, Keepsakes.Support.Message

    timestamps(updated_at: false)
  end

  @doc "Whether it can be shown inline as a picture."
  def image?(%__MODULE__{content_type: type}), do: String.starts_with?(type, "image/")
end
