defmodule Keepsakes.Sharing.GuestbookEntry do
  @moduledoc """
  A guestbook note. `"pending"` until the owner or an editor approves it;
  only `"approved"` notes are shown to other guests.
  """
  use Keepsakes.Schema

  schema "guestbook_entries" do
    field :visitor_key, :string
    field :name, :string
    field :message, :string
    field :status, :string, default: "pending"

    belongs_to :album, Keepsakes.Albums.Album
    belongs_to :share_link, Keepsakes.Sharing.ShareLink

    timestamps()
  end

  @doc "The guest's form: name and message."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:name, :message])
    |> update_change(:name, &String.trim/1)
    |> update_change(:message, &String.trim/1)
    |> validate_required([:name, :message])
    |> validate_length(:name, max: 60)
    |> validate_length(:message, max: 500)
  end

  def pending?(%__MODULE__{status: status}), do: status == "pending"
end
