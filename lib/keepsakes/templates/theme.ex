defmodule Keepsakes.Templates.Theme do
  @moduledoc """
  A template's look: colour and font slots layered over the renderer's
  defaults (the `--color-ks-guest-*` tokens in `app.css`, which are Trail's
  night palette). Only the slots a theme sets are emitted, so an empty
  theme is Trail as designed.

  Colours are `#RRGGBB` or `#RRGGBBAA`; fonts must be one of the
  self-hosted families. Every value is validated before it reaches a
  `style` attribute.
  """

  # slot => CSS custom property it sets
  @colors %{
    "page" => "--color-ks-guest",
    "ink" => "--color-ks-guest-ink",
    "text" => "--color-ks-guest-text",
    "card" => "--color-ks-guest-card",
    "line" => "--color-ks-guest-line",
    "field" => "--color-ks-guest-field",
    "bar" => "--color-ks-guest-bar",
    "edge" => "--color-ks-guest-edge",
    "paper" => "--color-ks-guest-paper",
    "shadow" => "--color-ks-guest-shadow",
    "primary" => "--color-primary",
    "primary_content" => "--color-primary-content",
    "secondary" => "--color-secondary",
    "accent" => "--color-accent",
    "accent_content" => "--color-accent-content"
  }

  @fonts %{"display_font" => "--font-display", "hand_font" => "--font-hand"}

  # Self-hosted in priv/static/fonts, with their fallbacks
  @families %{
    "Bricolage Grotesque" => ~s("Bricolage Grotesque", "DM Sans", ui-sans-serif, sans-serif),
    "DM Sans" => ~s("DM Sans", ui-sans-serif, system-ui, sans-serif),
    "DM Mono" => ~s("DM Mono", ui-monospace, monospace),
    "Caveat" => ~s("Caveat", "Segoe Print", cursive)
  }

  @color_format ~r/\A#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/

  @doc "Colour slot names."
  def color_slots, do: Map.keys(@colors)

  @doc "Font families a theme may use."
  def families, do: Map.keys(@families)

  @doc "`\"dark\"` (default) or `\"light\"`, for the browser's `color-scheme`."
  def scheme(%{"scheme" => "light"}), do: "light"
  def scheme(_theme), do: "dark"

  @doc "Errors as `[{slot, message}]`; `[]` when the theme is valid."
  @spec errors(map()) :: [{String.t(), String.t()}]
  def errors(theme) when is_map(theme) do
    Enum.flat_map(theme, fn
      {"scheme", value} when value in ["dark", "light"] -> []
      {"scheme", _} -> [{"scheme", "must be dark or light"}]
      {slot, value} when is_map_key(@colors, slot) -> color_error(slot, value)
      {slot, value} when is_map_key(@fonts, slot) -> font_error(slot, value)
      {slot, _} -> [{slot, "is not a theme setting"}]
    end)
  end

  defp color_error(slot, value) do
    if is_binary(value) and Regex.match?(@color_format, value),
      do: [],
      else: [{slot, "must be a colour like #1F5F5B"}]
  end

  defp font_error(slot, value) do
    if is_map_key(@families, value), do: [], else: [{slot, "is not an available font"}]
  end

  @doc """
  The theme as CSS custom properties for a `style` attribute, e.g.
  `"--color-ks-guest: #F7F3EC; --color-primary: #1F5F5B"`. Invalid
  values are dropped, never emitted.
  """
  @spec css_vars(map()) :: String.t()
  def css_vars(theme) when is_map(theme) do
    invalid = theme |> errors() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    theme
    |> Enum.reject(fn {slot, _} -> MapSet.member?(invalid, slot) end)
    |> Enum.sort()
    |> Enum.flat_map(fn
      {slot, value} when is_map_key(@colors, slot) -> ["#{@colors[slot]}: #{value}"]
      {slot, value} when is_map_key(@fonts, slot) -> ["#{@fonts[slot]}: #{@families[value]}"]
      _ -> []
    end)
    |> Enum.join("; ")
  end
end
