defmodule Keepsakes.Staff.Forbidden do
  @moduledoc "Raised when a staff member lacks a permission; shown as a 403 page."
  defexception message: "You don't have access to this.", plug_status: 403
end
