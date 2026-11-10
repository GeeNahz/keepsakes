defmodule Keepsakes.Staff.Membership do
  @moduledoc "Makes a user staff, with their roles. Inactive memberships grant nothing."
  use Keepsakes.Schema

  @type t :: %__MODULE__{}

  schema "staff_memberships" do
    field :active, :boolean, default: true

    belongs_to :user, Keepsakes.Accounts.User
    belongs_to :added_by, Keepsakes.Accounts.User

    many_to_many :roles, Keepsakes.Staff.Role,
      join_through: "staff_roles",
      join_keys: [membership_id: :id, role_id: :id],
      on_replace: :delete

    timestamps()
  end
end
