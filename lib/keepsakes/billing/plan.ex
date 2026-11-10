defmodule Keepsakes.Billing.Plan do
  @moduledoc """
  A plan: its kind (`free`, `trial` or `paid`), whether it's offered
  publicly, its feature values (see `Keepsakes.Billing.Features`) and,
  for paid plans, its prices.
  """
  use Keepsakes.Schema

  alias Keepsakes.Billing.{Features, Price}

  @type t :: %__MODULE__{}

  schema "plans" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :kind, :string
    field :public, :boolean, default: true
    field :position, :integer, default: 0
    field :features, :map, default: %{}

    has_many :prices, Price

    timestamps()
  end

  @doc "For the admin plan editor (and test fixtures)."
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:slug, :name, :description, :kind, :public, :position, :features])
    |> validate_required([:slug, :name, :kind])
    |> validate_format(:slug, ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/)
    |> validate_inclusion(:kind, ~w(free trial paid))
    |> validate_change(:features, fn :features, features ->
      Enum.map(Features.errors(features), fn {key, message} ->
        {:features, "#{key} #{message}"}
      end)
    end)
    |> unique_constraint(:slug)
  end
end
