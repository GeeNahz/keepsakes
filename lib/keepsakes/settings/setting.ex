defmodule Keepsakes.Settings.Setting do
  @moduledoc "A persisted override of one system setting. Value is stored as `%{\"v\" => value}`."
  use Keepsakes.Schema

  schema "system_settings" do
    field :key, :string
    field :value, :map
    field :updated_by_id, :binary_id

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
