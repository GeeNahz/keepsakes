defmodule Mix.Tasks.Keepsakes.Staff.Grant do
  @shortdoc "Gives an existing account admin portal access"

  @moduledoc """
  Makes an existing account staff with the given role (by key), for
  creating the first Super Admin when `SUPER_ADMIN_EMAIL` isn't used.

      $ mix keepsakes.staff.grant you@example.com --role super_admin
      $ mix keepsakes.staff.grant finance@example.com --role finance

  The account must already be registered. In a release:

      bin/keepsakes eval 'Keepsakes.Release.grant_staff("you@example.com", "super_admin")'
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    case OptionParser.parse(args, strict: [role: :string]) do
      {opts, [email], []} ->
        case Keepsakes.Release.grant_staff(email, opts[:role] || "super_admin") do
          :ok -> Mix.shell().info("#{email} now has #{opts[:role] || "super_admin"} access")
          {:error, message} -> Mix.raise(message)
        end

      _ ->
        Mix.raise("Usage: mix keepsakes.staff.grant EMAIL --role super_admin")
    end
  end
end
