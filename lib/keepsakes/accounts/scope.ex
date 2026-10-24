defmodule Keepsakes.Accounts.Scope do
  @moduledoc """
  The scope of the caller, passed as the first argument to every context
  function that reads or writes tenant data.

  Keepsake is multi-tenant with a shared schema: every owned row carries a
  `user_id`, and context queries filter by `scope.user.id`, so one owner can
  never read another owner's albums.

  Fields:

    * `:user` - the logged-in `Keepsakes.Accounts.User`, or `nil`
    * `:subscription` - the user's current subscription (Stage 5)
    * `:entitlements` - feature key => value for the user's plan, e.g.
      `%{"max_albums" => 3, "guest_downloads" => true}` (Stage 5)
  """

  alias Keepsakes.Accounts.User

  defstruct user: nil, subscription: nil, entitlements: %{}

  @type t :: %__MODULE__{
          user: User.t() | nil,
          subscription: struct() | nil,
          entitlements: map()
        }

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil
end
