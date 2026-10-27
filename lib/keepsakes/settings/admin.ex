defmodule Keepsakes.Settings.Admin do
  @moduledoc """
  System settings as staff change them in the admin portal
  (`config.manage`). Only values that differ are saved; each change and
  reset is audited with before/after.
  """
  alias Keepsakes.{Audit, Settings, Staff}
  alias Keepsakes.Staff.Scope

  @doc """
  Saves the form's values (`%{"trial_days" => "30", ...}`). Returns
  `{:ok, changed_keys}` or `{:error, %{key => :invalid}}` (nothing saved).
  """
  def save(%Scope{} = scope, params) do
    Staff.authorize!(scope, "config.manage")
    defs = Settings.definitions()

    casted =
      for {key, {type, _default, _desc}} <- defs, Map.has_key?(params, to_string(key)) do
        {key, cast(type, params[to_string(key)])}
      end

    case Enum.filter(casted, fn {_k, v} -> v == :error end) do
      [] ->
        changed =
          for {key, {:ok, value}} <- casted, Settings.get(key) != value do
            before = Settings.get(key)
            {:ok, _} = Settings.put(key, value, updated_by_id: scope.user.id)

            Audit.record(scope, "setting.changed", {"setting", key, to_string(key)}, %{
              "before" => before,
              "after" => value
            })

            key
          end

        {:ok, changed}

      bad ->
        {:error, Map.new(bad, fn {k, _} -> {k, :invalid} end)}
    end
  end

  @doc "Puts `key` back to its default."
  def reset(%Scope{} = scope, key) do
    Staff.authorize!(scope, "config.manage")
    before = Settings.get(key)
    :ok = Settings.reset(key)

    Audit.record(scope, "setting.reset", {"setting", key, to_string(key)}, %{
      "before" => before,
      "after" => Settings.get(key)
    })

    :ok
  end

  defp cast(:integer, value) do
    case Integer.parse(String.trim(to_string(value))) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp cast(:boolean, value), do: {:ok, value in [true, "true"]}

  defp cast(:string, value) do
    case String.trim(to_string(value)) do
      "" -> :error
      text -> {:ok, String.slice(text, 0, 500)}
    end
  end
end
