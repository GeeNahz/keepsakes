defmodule Keepsakes.Domains.BlockedHostname do
  @moduledoc "A name staff never allow as a custom domain: exact, or `*.example.com`."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "blocked_hostnames" do
    field :pattern, :string
    field :reason, :string

    belongs_to :added_by, Keepsakes.Accounts.User

    timestamps()
  end

  def changeset(blocked, attrs) do
    blocked
    |> cast(attrs, [:pattern, :reason])
    |> update_change(:pattern, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:pattern, :reason])
    |> validate_format(:pattern, ~r/\A(\*\.)?([a-z0-9-]+\.)+[a-z]{2,}\z/,
      message: "use a name like example.com or *.example.com"
    )
    |> unique_constraint(:pattern)
  end

  @doc "Whether `hostname` matches `pattern`."
  def match?(%__MODULE__{pattern: "*." <> base}, hostname),
    do: hostname == base or String.ends_with?(hostname, "." <> base)

  def match?(%__MODULE__{pattern: pattern}, hostname), do: hostname == pattern
end
