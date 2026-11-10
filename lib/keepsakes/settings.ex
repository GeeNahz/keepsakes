defmodule Keepsakes.Settings do
  @moduledoc """
  Typed, admin-editable system configuration.

  Every setting has a type and a default defined in `@definitions`; only
  values changed from the admin portal are stored in `system_settings`.
  Reads are cached in ETS (`Keepsakes.Settings.Cache`) and the cache is
  cleared on every node over PubSub when a value changes.

      Keepsakes.Settings.get(:trial_days)
      #=> 60
  """
  import Ecto.Query

  alias Keepsakes.Repo
  alias Keepsakes.Settings.{Cache, Setting}

  @definitions [
    trial_days: {:integer, 60, "Length of the free trial every new user starts on, in days"},
    grace_days:
      {:integer, 7, "Full-access grace period after a trial or failed renewal, in days"},
    image_long_edge:
      {:integer, 2400, "Uploaded photos are resized to this many pixels on the long edge"},
    image_quality: {:integer, 82, "Compression quality (1-100) for stored photos"},
    max_upload_mb:
      {:integer, 25,
       "Hard ceiling on a single upload, in MB (each plan sets its own, up to this)"},
    signups_open: {:boolean, true, "Allow new users to register"},
    maintenance_mode: {:boolean, false, "Show the maintenance page to everyone except staff"},
    maintenance_message:
      {:string, "We're making Keepsake better. Back shortly.",
       "Message shown on the maintenance page"},
    default_template: {:string, "trail", "Template slug attached to new albums"},
    sla_urgent_hours: {:integer, 4, "Hours to the first staff reply on an urgent ticket"},
    sla_high_hours: {:integer, 8, "Hours to the first staff reply on a high-priority ticket"},
    sla_normal_hours: {:integer, 24, "Hours to the first staff reply on a normal ticket"},
    sla_low_hours: {:integer, 72, "Hours to the first staff reply on a low-priority ticket"}
  ]

  # How the admin portal's settings page groups them
  @groups [
    {"Trial & billing", [:trial_days, :grace_days]},
    {"Uploads", [:image_long_edge, :image_quality, :max_upload_mb]},
    {"Sign-ups", [:signups_open]},
    {"Templates", [:default_template]},
    {"Support targets", [:sla_urgent_hours, :sla_high_hours, :sla_normal_hours, :sla_low_hours]},
    {"Maintenance", [:maintenance_mode, :maintenance_message]}
  ]

  @keys Keyword.keys(@definitions)

  @type key :: atom()

  @doc "All setting definitions as `{key, {type, default, description}}`."
  def definitions, do: @definitions

  @doc "Settings grouped for the admin portal, as `[{title, [key]}]`."
  def groups, do: @groups

  @doc "Whether `key` has a stored value (otherwise its default applies)."
  def overridden?(key) when key in @keys,
    do: Repo.exists?(from s in Setting, where: s.key == ^Atom.to_string(key))

  @doc "Current value of `key` (stored override or default)."
  @spec get(key) :: term()
  def get(key) when key in @keys do
    case Cache.fetch(key) do
      {:ok, value} -> value
      :miss -> key |> load() |> tap(&Cache.put(key, &1))
    end
  end

  @doc "All settings as a keyword list of current values."
  def all, do: Enum.map(@keys, &{&1, get(&1)})

  @doc """
  Stores `value` for `key` after casting it to the setting's type.
  Accepts string input (e.g. from forms). Returns `{:error, :invalid}` when
  the value can't be cast.
  """
  @spec put(key | String.t(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def put(key, value, opts \\ [])

  def put(key, value, opts) when is_binary(key) do
    case Enum.find(@keys, &(Atom.to_string(&1) == key)) do
      nil -> {:error, :unknown_setting}
      atom -> put(atom, value, opts)
    end
  end

  def put(key, value, opts) when key in @keys do
    {type, _default, _desc} = Keyword.fetch!(@definitions, key)

    with {:ok, cast} <- cast(type, value),
         {:ok, _} <- upsert(key, cast, opts[:updated_by_id]) do
      Cache.invalidate(key)
      {:ok, cast}
    end
  end

  @doc "Removes a stored override so `key` falls back to its default."
  def reset(key) when key in @keys do
    Repo.delete_all(from s in Setting, where: s.key == ^Atom.to_string(key))
    Cache.invalidate(key)
    :ok
  end

  defp load(key) do
    {type, default, _desc} = Keyword.fetch!(@definitions, key)

    case Repo.get_by(Setting, key: Atom.to_string(key)) do
      %Setting{value: %{"v" => stored}} ->
        case cast(type, stored) do
          {:ok, value} -> value
          {:error, _} -> default
        end

      nil ->
        default
    end
  end

  defp upsert(key, value, updated_by_id) do
    %Setting{}
    |> Setting.changeset(%{key: Atom.to_string(key), value: %{"v" => value}})
    |> Ecto.Changeset.put_change(:updated_by_id, updated_by_id)
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_by_id, :updated_at]},
      conflict_target: :key
    )
  end

  defp cast(:integer, v) when is_integer(v), do: {:ok, v}

  defp cast(:integer, v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid}
    end
  end

  defp cast(:boolean, v) when is_boolean(v), do: {:ok, v}
  defp cast(:boolean, v) when v in ["true", "1", "on"], do: {:ok, true}
  defp cast(:boolean, v) when v in ["false", "0", "off", ""], do: {:ok, false}
  defp cast(:string, v) when is_binary(v), do: {:ok, v}
  defp cast(_type, _v), do: {:error, :invalid}
end
