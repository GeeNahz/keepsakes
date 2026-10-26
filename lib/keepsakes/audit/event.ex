defmodule Keepsakes.Audit.Event do
  @moduledoc "One recorded admin change (see `Keepsakes.Audit`)."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "audit_events" do
    field :actor_email, :string
    field :action, :string
    field :target_type, :string
    field :target_id, :string
    field :target_label, :string
    field :changes, :map, default: %{}
    field :ip, :string

    belongs_to :actor, Keepsakes.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
