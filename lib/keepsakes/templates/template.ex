defmodule Keepsakes.Templates.Template do
  @moduledoc """
  A guest template: a renderer (the code that draws the access, timeline
  and slideshow pages) plus a theme (colours and fonts, see
  `Keepsakes.Templates.Theme`). Public templates have no `user_id`; a
  user's own private templates (planned) will.
  """
  use Keepsakes.Schema

  alias Keepsakes.Templates.Theme

  @type t :: %__MODULE__{}

  schema "templates" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :renderer, :string, default: "trail"
    field :theme, :map, default: %{}
    field :premium, :boolean, default: false
    field :active, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :user, Keepsakes.Accounts.User

    timestamps()
  end

  @doc "For the admin template editor (and test fixtures)."
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:slug, :name, :description, :renderer, :theme, :premium, :active, :position])
    |> validate_required([:slug, :name, :renderer])
    |> validate_format(:slug, ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/)
    |> validate_length(:name, max: 40)
    |> validate_length(:description, max: 140)
    |> validate_inclusion(:renderer, Keepsakes.Templates.renderers())
    |> validate_change(:theme, fn :theme, theme ->
      Enum.map(Theme.errors(theme), fn {slot, message} -> {:theme, "#{slot} #{message}"} end)
    end)
    |> unique_constraint(:slug)
  end
end
