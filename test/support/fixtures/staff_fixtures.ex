defmodule Keepsakes.StaffFixtures do
  @moduledoc "Staff members and admin portal sessions for tests."
  import Keepsakes.AccountsFixtures

  alias Keepsakes.{Accounts, Repo, Staff}
  alias Keepsakes.Staff.Role

  def role(key), do: Repo.get_by!(Role, key: key)

  @doc "A confirmed user who is staff with the roles keyed `role_keys`."
  def staff_fixture(role_keys \\ ["super_admin"], attrs \\ %{}) do
    user = user_fixture(attrs) |> set_password()
    {:ok, _} = Staff.grant(:system, user.email, Enum.map(role_keys, &role(&1).id))
    user
  end

  def staff_scope_fixture(role_keys \\ ["super_admin"]) do
    role_keys |> staff_fixture() |> Staff.scope_for("127.0.0.1")
  end

  @doc "Points the conn at the admin portal's host."
  def admin_host(conn), do: %{conn | host: KeepsakesWeb.Hosts.admin_host()}

  @doc "An admin portal session for `user`, on the admin host."
  def log_in_staff(conn, user) do
    token = Accounts.generate_staff_session_token(user)

    conn
    |> admin_host()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:staff_token, token)
  end
end
