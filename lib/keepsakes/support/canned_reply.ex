defmodule Keepsakes.Support.CannedReply do
  @moduledoc "A saved answer staff can drop into a reply and edit before sending."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "canned_replies" do
    field :title, :string
    field :body, :string

    timestamps()
  end

  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:title, :body])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 80)
    |> validate_length(:body, max: 5000)
    |> unique_constraint(:title, message: "There's already a reply with this title")
  end
end
