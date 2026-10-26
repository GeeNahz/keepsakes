defmodule Keepsakes.StaffBootstrapTest do
  # Not async: changes the :super_admin_email setting and Mix.shell
  use Keepsakes.DataCase, async: false

  import Keepsakes.AccountsFixtures

  alias Keepsakes.Staff

  describe "SUPER_ADMIN_EMAIL" do
    setup do
      Application.put_env(:keepsakes, :super_admin_email, "owner@example.com")
      on_exit(fn -> Application.delete_env(:keepsakes, :super_admin_email) end)
    end

    test "that address becomes Super Admin when it signs up" do
      user = user_fixture(email: "owner@example.com")
      assert Staff.scope_for(user).super_admin?
    end

    test "nobody else does" do
      refute Staff.staff?(user_fixture())
    end
  end

  describe "mix keepsakes.staff.grant" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    test "grants a role and keeps the ones already held" do
      user = user_fixture()
      Mix.Tasks.Keepsakes.Staff.Grant.run([user.email, "--role", "finance"])
      assert_received {:mix_shell, :info, [_]}

      Mix.Tasks.Keepsakes.Staff.Grant.run([user.email, "--role", "support"])
      keys = Staff.get_membership(user).roles |> Enum.map(& &1.key) |> Enum.sort()
      assert keys == ["finance", "support"]
    end

    test "defaults to Super Admin" do
      user = user_fixture()
      Mix.Tasks.Keepsakes.Staff.Grant.run([user.email])
      assert Staff.scope_for(user).super_admin?
    end

    test "explains a missing account or role" do
      assert_raise Mix.Error, ~r/sign up first/, fn ->
        Mix.Tasks.Keepsakes.Staff.Grant.run(["nobody@example.com"])
      end

      assert_raise Mix.Error, ~r/No role/, fn ->
        Mix.Tasks.Keepsakes.Staff.Grant.run([user_fixture().email, "--role", "wizard"])
      end
    end
  end
end
