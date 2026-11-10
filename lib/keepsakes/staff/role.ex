defmodule Keepsakes.Staff.Role do
  @moduledoc """
  A named set of permissions. `system` roles (Super Admin) are locked and
  hold every permission.
  """
  use Keepsakes.Schema

  alias Keepsakes.Staff.Permissions

  @type t :: %__MODULE__{}

  schema "roles" do
    field :key, :string
    field :name, :string
    field :description, :string
    field :system, :boolean, default: false
    field :permissions, {:array, :string}, default: []

    timestamps()
  end

  @doc "For the role editor (system roles are refused by the context)."
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :permissions])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 40)
    |> validate_length(:description, max: 160)
    |> update_change(:permissions, fn perms ->
      perms |> Enum.uniq() |> Enum.filter(&Permissions.known?/1)
    end)
    |> put_key()
    |> unique_constraint(:key, message: "A role with this name already exists")
  end

  defp put_key(changeset) do
    if changeset.data.id do
      changeset
    else
      case get_field(changeset, :name) do
        nil ->
          changeset

        name ->
          put_change(
            changeset,
            :key,
            name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
          )
      end
    end
  end
end
