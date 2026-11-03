defmodule Keepsakes.Sharing.Reaction do
  @moduledoc "A guest's heart on a photo: one per browser (`visitor_key`) per photo."
  use Keepsakes.Schema

  schema "memory_reactions" do
    field :visitor_key, :string

    belongs_to :memory, Keepsakes.Albums.Memory
    belongs_to :share_link, Keepsakes.Sharing.ShareLink

    timestamps(updated_at: false)
  end
end
