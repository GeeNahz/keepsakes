defmodule Keepsakes.Albums.NotAllowed do
  @moduledoc """
  Raised when someone acts on an album they have no (or too little) access
  to. Shown as 404, so it doesn't reveal that the album exists.
  """
  defexception message: "Album not found", plug_status: 404
end
