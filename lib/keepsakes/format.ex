defmodule Keepsakes.Format do
  @moduledoc "Human-friendly formatting shared by pages and emails."

  @doc "Human size: `\"38 MB\"`, `\"1 GB\"`, `\"0 MB\"`."
  def bytes(bytes) when bytes >= 1024 * 1024 * 1024 do
    gb = bytes / (1024 * 1024 * 1024)
    if gb == trunc(gb), do: "#{trunc(gb)} GB", else: "#{Float.round(gb, 1)} GB"
  end

  def bytes(bytes) when bytes >= 1024 * 1024 * 10, do: "#{round(bytes / (1024 * 1024))} MB"

  def bytes(bytes) when bytes >= 1024 * 100,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  def bytes(bytes) when bytes > 0, do: "#{max(round(bytes / 1024), 1)} KB"
  def bytes(_), do: "0 MB"
end
