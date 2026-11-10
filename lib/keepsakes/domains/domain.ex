defmodule Keepsakes.Domains.Domain do
  @moduledoc """
  A customer's own web address for their public site. `pending` until DNS
  proves they own it (TXT `_keepsake.<hostname>` holds the token) and
  points it at our edge; then `verified`. `failed` when that didn't happen
  in time or stopped being true; `blocked` by staff.
  """
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "domains" do
    field :hostname, :string
    field :status, :string, default: "pending"
    field :verification_token, :string
    field :verified_at, :utc_datetime
    field :last_checked_at, :utc_datetime
    field :checks, :integer, default: 0
    field :last_error, :string
    field :blocked_reason, :string

    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "The TXT record's name for this domain."
  def txt_name(%__MODULE__{hostname: host}), do: "_keepsake." <> host

  @doc "Whether the hostname is a root domain (no CNAME allowed there, so an A record)."
  def apex?(%__MODULE__{hostname: host}), do: host |> String.split(".") |> length() == 2
end
