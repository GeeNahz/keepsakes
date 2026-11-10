defmodule KeepsakesWeb.AdminLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Staff}

  describe "navigation by permission" do
    test "Super Admin sees every section", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/")

      for key <- ~w(dashboard staff roles audit) do
        assert has_element?(view, "#admin-nav-#{key}")
      end
    end

    test "Finance doesn't see staff, roles or the audit log", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture(["finance"])) |> live(~p"/")

      assert has_element?(view, "#admin-nav-dashboard")
      refute has_element?(view, "#admin-nav-staff")
      refute has_element?(view, "#admin-nav-roles")
      refute has_element?(view, "#admin-nav-audit")
    end

    test "pages without the permission are a 403", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["finance"]))

      for path <- [~p"/staff", ~p"/roles", ~p"/roles/new", ~p"/audit"] do
        assert_error_sent 403, fn -> get(conn, path) end
      end
    end
  end

  describe "dashboard" do
    test "counts customers and leaves staff out", %{conn: conn} do
      staff = staff_fixture()
      _customer = user_fixture()

      {:ok, view, _html} = conn |> log_in_staff(staff) |> live(~p"/")
      assert view |> element("#stat-customers") |> render() =~ ">1<"
      assert has_element?(view, "#signups-chart svg")
      assert has_element?(view, "#uploads-chart svg")
      assert has_element?(view, "#stat-mrr-ngn")
    end

    test "staff without dashboard.view get a welcome instead", %{conn: conn} do
      {:ok, role} =
        Staff.create_role(staff_scope_fixture(), %{
          "name" => "Auditors",
          "permissions" => ["audit.view"]
        })

      {:ok, view, _html} = conn |> log_in_staff(staff_fixture([role.key])) |> live(~p"/")
      refute has_element?(view, "#dashboard-stats")
      assert has_element?(view, "#admin-nav-audit")
    end
  end

  describe "staff page" do
    setup %{conn: conn} do
      admin = staff_fixture()
      %{conn: log_in_staff(conn, admin), admin: admin}
    end

    test "adds an existing account as staff", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/staff")

      view |> element("#add-staff") |> render_click()
      assert has_element?(view, "#staff-form")

      view
      |> form("#staff-form", staff: %{email: user.email, role_ids: [role("support").id]})
      |> render_submit()

      refute has_element?(view, "#staff-form")
      assert Staff.staff?(user)
      assert has_element?(view, "#staff-#{Staff.get_membership(user).id}")
    end

    test "explains when there's no such account", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff")
      view |> element("#add-staff") |> render_click()

      view
      |> form("#staff-form",
        staff: %{email: "nobody@example.com", role_ids: [role("support").id]}
      )
      |> render_submit()

      assert has_element?(view, "#staff-form-error")
    end

    test "removes staff after a confirmation", %{conn: conn} do
      user = staff_fixture(["support"])
      id = Staff.get_membership(user).id
      {:ok, view, _html} = live(conn, ~p"/staff")

      view |> element("#remove-staff-#{id}") |> render_click()
      view |> element("#confirm-remove-staff-#{id}") |> render_click()

      refute Staff.staff?(user)
    end

    test "you can't remove yourself", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/staff")
      refute has_element?(view, "#remove-staff-#{Staff.get_membership(admin).id}")
    end
  end

  describe "roles" do
    setup %{conn: conn} do
      %{conn: log_in_staff(conn, staff_fixture())}
    end

    test "lists roles; Super Admin can't be edited", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roles")
      assert has_element?(view, "#edit-role-#{role("finance").id}")
      refute has_element?(view, "#edit-role-#{role("super_admin").id}")

      assert {:error, {:live_redirect, %{to: "/roles"}}} =
               live(conn, ~p"/roles/#{role("super_admin").id}")
    end

    test "creates a role with permissions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roles/new")

      view
      |> form("#role-form", role: %{name: "Content", permissions: ["", "templates.manage"]})
      |> render_submit()

      assert_redirect(view, ~p"/roles")

      assert Keepsakes.Repo.get_by!(Staff.Role, key: "content").permissions == [
               "templates.manage"
             ]
    end

    test "edits and deletes a role", %{conn: conn} do
      id = role("support").id
      {:ok, view, _html} = live(conn, ~p"/roles/#{id}")

      view |> form("#role-form", role: %{name: "Customer care"}) |> render_submit()
      assert_redirect(view, ~p"/roles")
      assert Keepsakes.Repo.get!(Staff.Role, id).name == "Customer care"

      {:ok, view, _html} = live(conn, ~p"/roles/#{id}")
      view |> element("#delete-role") |> render_click()
      view |> element("#confirm-delete-role") |> render_click()
      assert_redirect(view, ~p"/roles")
      refute Keepsakes.Repo.get(Staff.Role, id)
    end
  end

  describe "audit log" do
    test "shows changes and filters by section", %{conn: conn} do
      admin = staff_scope_fixture()
      {:ok, _} = Staff.create_role(admin, %{"name" => "Content", "permissions" => []})
      {:ok, _} = Staff.grant(admin, user_fixture().email, [role("support").id])

      {:ok, view, _html} = conn |> log_in_staff(admin.user) |> live(~p"/audit")
      [role_event] = Audit.list(admin, %{"action" => "role."})
      # Newest first (the fixture's own grant comes after)
      [staff_event | _] = Audit.list(admin, %{"action" => "staff.granted"})

      assert has_element?(view, "#events-#{role_event.id}")
      assert has_element?(view, "#events-#{staff_event.id}")

      view |> form("#audit-filters", audit: %{action: "role"}) |> render_change()
      assert has_element?(view, "#events-#{role_event.id}")
      refute has_element?(view, "#events-#{staff_event.id}")
    end
  end
end
