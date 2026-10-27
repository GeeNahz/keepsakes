defmodule KeepsakesWeb.MaintenanceHTML do
  @moduledoc "The page `KeepsakesWeb.Maintenance` shows while maintenance mode is on."
  use KeepsakesWeb, :html

  embed_templates "maintenance_html/*"
end
