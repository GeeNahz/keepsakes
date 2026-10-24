defmodule Keepsakes.Albums.Album do
  @moduledoc "An album: one story (a child growing up, a trip, a wedding)."
  use Keepsakes.Schema

  alias Keepsakes.Albums.Memory

  @type t :: %__MODULE__{}

  schema "albums" do
    field :name, :string
    field :slug, :string
    field :description, :string
    # Published memories, filled in by list queries
    field :memories_count, :integer, virtual: true, default: 0

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :cover_memory, Memory
    has_many :memories, Memory

    timestamps()
  end

  @doc "Name and description, as typed in the New album dialog."
  def changeset(album, attrs) do
    album
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &squish/1)
    |> update_change(:description, &squish/1)
    |> validate_required([:name], message: "Give your album a name")
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 140)
  end

  @doc "Sets the slug derived from the name. `taken` lists the owner's slugs."
  def put_slug(changeset, taken) do
    case get_field(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, unique_slug(slugify(name), MapSet.new(taken)))
    end
  end

  @doc "URL-safe slug: lowercase ASCII words joined by dashes."
  def slugify(name) do
    slug =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 60)
      |> String.trim("-")

    if slug == "", do: "album", else: slug
  end

  defp unique_slug(base, taken) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp squish(nil), do: nil

  defp squish(value) do
    case value |> String.trim() |> String.replace(~r/\s+/, " ") do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
