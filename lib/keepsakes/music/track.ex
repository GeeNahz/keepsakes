defmodule Keepsakes.Music.Track do
  @moduledoc """
  A slideshow music track.

    * `"upload"` - an owner's own file (`user_id` set), counted in their storage
    * `"library"` - reserved for a built-in library (no `user_id`); not
      offered yet, but albums and guests play it the same way
  """
  use Keepsakes.Schema

  schema "music_tracks" do
    field :source, :string, default: "upload"
    field :storage_key, :string
    field :filename, :string
    field :content_type, :string
    field :bytes, :integer, default: 0
    field :title, :string
    field :duration_seconds, :integer

    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "What to call the track in the owner's settings."
  def label(%__MODULE__{title: title}) when is_binary(title) and title != "", do: title
  def label(%__MODULE__{filename: filename}) when is_binary(filename), do: filename
  def label(_track), do: "Music"
end
