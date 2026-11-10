defmodule Keepsakes.Billing.Features do
  @moduledoc """
  The feature catalogue: every key a plan can set, and how it is read.

  The catalogue lives in code rather than a table because each key needs
  code that enforces it; plans only choose the values (`plans.features`,
  editable in the admin portal). A key a plan doesn't set falls back to
  the catalogue default, which is always the most restrictive value.

    * `:limit` - an integer, or `nil` for unlimited (`unit` says what it counts)
    * `:boolean` - on or off
  """

  @catalogue [
    {:max_albums, :limit, :count, "Albums"},
    {:max_memories_per_album, :limit, :count, "Photos per album"},
    {:storage_bytes, :limit, :bytes, "Storage"},
    {:max_upload_mb, :limit, :mb, "Largest photo"},
    {:collaborator_seats, :limit, :count, "Collaborators"},
    {:custom_domains, :limit, :count, "Custom domains"},
    {:premium_templates, :boolean, nil, "Premium templates"},
    {:guest_downloads, :boolean, nil, "Guests can download photos"},
    {:remove_branding, :boolean, nil, "No \"Made with Keepsake\""},
    {:guest_uploads, :boolean, nil, "Guest uploads"},
    {:time_capsule, :boolean, nil, "Time capsule"},
    {:reactions_guestbook, :boolean, nil, "Reactions and guestbook"},
    {:slideshow_music, :boolean, nil, "Slideshow music"}
  ]

  @keys Enum.map(@catalogue, &elem(&1, 0))

  @type key :: atom()

  @doc "Every feature as `%{key, kind, unit, name}`, in display order."
  def all do
    for {key, kind, unit, name} <- @catalogue, do: %{key: key, kind: kind, unit: unit, name: name}
  end

  @doc "All feature keys."
  def keys, do: @keys

  @doc "`:limit` or `:boolean`."
  def kind(key) when key in @keys,
    do: @catalogue |> List.keyfind(key, 0) |> elem(1)

  @doc """
  The plan's value for `key`, read from its `features` map (string keys).
  Missing limits are 0 and missing booleans false.
  """
  def value(features, key) when key in @keys and is_map(features) do
    case {kind(key), Map.fetch(features, Atom.to_string(key))} do
      {:limit, {:ok, value}} when is_integer(value) and value >= 0 -> value
      {:limit, {:ok, nil}} -> :unlimited
      {:limit, _} -> 0
      {:boolean, {:ok, true}} -> true
      {:boolean, _} -> false
    end
  end

  @doc "Errors as `[{key, message}]` for a plan's features map; `[]` when valid."
  def errors(features) when is_map(features) do
    by_name = Map.new(@keys, &{Atom.to_string(&1), &1})

    Enum.flat_map(features, fn {name, value} ->
      case {Map.fetch(by_name, name), value} do
        {:error, _} -> [{name, "is not a feature"}]
        {{:ok, key}, value} -> value_error(kind(key), name, value)
      end
    end)
  end

  defp value_error(:limit, _name, value) when is_nil(value) or (is_integer(value) and value >= 0),
    do: []

  defp value_error(:limit, name, _), do: [{name, "must be a whole number or unlimited"}]
  defp value_error(:boolean, _name, value) when is_boolean(value), do: []
  defp value_error(:boolean, name, _), do: [{name, "must be on or off"}]
end
