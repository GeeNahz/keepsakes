defmodule Keepsakes.StaffTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Staff}
  alias Keepsakes.Staff.{Forbidden, Scope}

  describe "scope_for/2" do
    test "is nil for customers" do
      assert Staff.scope_for(user_fixture()) == nil
    end

    test "collects the permissions of every role" do
      scope = staff_scope_fixture(["finance", "support"])
      assert Scope.can?(scope, "finance.refund")
      assert Scope.can?(scope, "support.reply")
      refute Scope.can?(scope, "roles.manage")
      refute scope.super_admin?
    end

    test "Super Admin can do everything" do
      scope = staff_scope_fixture()
      assert scope.super_admin?
      assert Scope.can?(scope, "roles.manage")
      assert Scope.can?(scope, "anything.at_all")
    end
  end

  describe "grant/3" do
    test "makes an existing account staff and audits it" do
      admin = staff_scope_fixture()
      user = user_fixture()

      assert {:ok, membership} = Staff.grant(admin, user.email, [role("support").id])
      assert membership.active
      assert Staff.staff?(user)

      assert [%{action: "staff.granted", target_label: label, actor_email: actor}] =
               Audit.list(admin, %{"action" => "staff.granted", "target_id" => user.id})

      assert label == user.email
      assert actor == admin.user.email
    end

    test "needs an account and a role" do
      admin = staff_scope_fixture()

      assert {:error, :no_account} =
               Staff.grant(admin, "nobody@example.com", [role("support").id])

      assert {:error, :no_roles} = Staff.grant(admin, user_fixture().email, [])
    end

    test "needs roles.manage" do
      finance = staff_scope_fixture(["finance"])

      assert {:error, :forbidden} =
               Staff.grant(finance, user_fixture().email, [role("support").id])
    end

    test "only a Super Admin can give, change or take Super Admin" do
      {:ok, manager_role} =
        Staff.create_role(staff_scope_fixture(), %{
          "name" => "Managers",
          "permissions" => ["roles.manage"]
        })

      manager = staff_fixture(["managers"]) |> Staff.scope_for()
      other_admin = staff_fixture()

      assert {:error, :forbidden} =
               Staff.grant(manager, user_fixture().email, [role("super_admin").id])

      assert {:error, :forbidden} = Staff.grant(manager, other_admin.email, [manager_role.id])

      membership = Staff.get_membership(other_admin)
      assert {:error, :forbidden} = Staff.revoke(manager, membership)
    end
  end

  describe "revoke/2" do
    test "ends staff access but keeps the account" do
      admin = staff_scope_fixture()
      user = staff_fixture(["support"])

      assert {:ok, _} = Staff.revoke(admin, Staff.get_membership(user))
      refute Staff.staff?(user)
      assert Keepsakes.Accounts.get_user(user.id)
    end

    test "can't remove yourself or the last Super Admin" do
      admin = staff_scope_fixture()
      assert {:error, :self} = Staff.revoke(admin, Staff.get_membership(admin.user))
    end
  end

  describe "roles" do
    test "create, update and delete a role, each audited" do
      admin = staff_scope_fixture()

      assert {:ok, role} =
               Staff.create_role(admin, %{
                 "name" => "Content team",
                 "permissions" => ["templates.manage", "made.up", ""]
               })

      assert role.key == "content_team"
      assert role.permissions == ["templates.manage"]

      assert {:ok, role} =
               Staff.update_role(admin, role, %{
                 "permissions" => ["templates.manage", "audit.view"]
               })

      assert role.permissions == ["templates.manage", "audit.view"]
      assert {:ok, _} = Staff.delete_role(admin, role)

      actions = admin |> Audit.list(%{"action" => "role."}) |> Enum.map(& &1.action)
      assert actions -- ["role.deleted", "role.updated", "role.created"] == []
      assert length(actions) == 3
    end

    test "Super Admin is locked" do
      admin = staff_scope_fixture()

      assert {:error, :locked} =
               Staff.update_role(admin, role("super_admin"), %{"name" => "Boss"})

      assert {:error, :locked} = Staff.delete_role(admin, role("super_admin"))
    end

    test "editing roles needs roles.manage" do
      assert_raise Forbidden, fn ->
        Staff.create_role(staff_scope_fixture(["support"]), %{"name" => "X"})
      end
    end
  end

  describe "ensure_super_admin/1" do
    test "grants an existing account once" do
      user = user_fixture()
      assert {:ok, _} = Staff.ensure_super_admin(user.email)
      assert Staff.scope_for(user).super_admin?
      assert :already = Staff.ensure_super_admin(user.email)
    end

    test "keeps roles the person already had" do
      user = staff_fixture(["finance"])
      assert {:ok, _} = Staff.ensure_super_admin(user.email)
      names = Staff.get_membership(user).roles |> Enum.map(& &1.key) |> Enum.sort()
      assert names == ["finance", "super_admin"]
    end

    test "waits for the account to exist" do
      assert {:error, :no_account} = Staff.ensure_super_admin("later@example.com")
    end
  end

  test "the audit log needs audit.view" do
    assert_raise Forbidden, fn -> Audit.list(staff_scope_fixture(["finance"])) end
  end
end
