defmodule Keepsakes.Schema do
  @moduledoc """
  `use Keepsakes.Schema` in every Ecto schema instead of `use Ecto.Schema`.

  It enforces the project-wide UUID convention (`--binary-id`): a
  `:binary_id` primary key, `:binary_id` foreign keys, and UTC timestamps.
  """
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
