defmodule Keepsakes.Exports.DataExport do
  @moduledoc """
  An "Export everything" zip: `pending` while it's built, then `ready`
  (downloadable until `expires_at`), `failed`, or `expired` once removed.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "data_exports" do
    field :status, :string, default: "pending"
    field :storage_key, :string
    field :bytes, :integer
    field :expires_at, :utc_datetime

    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end
end
