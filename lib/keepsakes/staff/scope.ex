defmodule Keepsakes.Staff.Scope do
  @moduledoc """
  Who is acting in the admin portal: the staff user, their permissions
  (all of them for Super Admin) and the IP the request came from (for the
  audit log). Passed first to every admin context function.
  """
  alias Keepsakes.Accounts.User

  defstruct [:user, :ip, permissions: MapSet.new(), super_admin?: false]

  @type t :: %__MODULE__{
          user: User.t(),
          ip: String.t() | nil,
          permissions: MapSet.t(String.t()),
          super_admin?: boolean()
        }

  @doc "Whether this staff member holds `permission`."
  def can?(%__MODULE__{super_admin?: true}, _permission), do: true
  def can?(%__MODULE__{permissions: perms}, permission), do: MapSet.member?(perms, permission)
end
