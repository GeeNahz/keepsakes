defmodule Keepsakes.Repo.Migrations.AddFunWithFlagsToggles do
  use Ecto.Migration

  # Table layout required by FunWithFlags' Ecto store, with a UUID primary
  # key to match `ecto_primary_key_type: :binary_id` in config.exs.
  def change do
    create table(:fun_with_flags_toggles) do
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end

    create unique_index(:fun_with_flags_toggles, [:flag_name, :gate_type, :target],
             name: "fwf_flag_name_gate_target_idx"
           )
  end
end
