defmodule KeepsakesWeb.AdminPlatformLiveTest do
  # Not async: the settings page writes shared (ETS-cached) settings
  use KeepsakesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Flags, Repo, Settings, Support}
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Support.Admin, as: SupportAdmin

  setup do
    on_exit(fn -> Enum.each(Keyword.keys(Settings.definitions()), &Settings.reset/1) end)
    customer = user_fixture()

    {:ok, ticket} =
      Support.create_ticket(Scope.for_user(customer), %{
        "category" => "technical",
        "subject" => "Upload stuck",
        "body" => "It stops at 80%"
      })

    %{customer: customer, ticket: ticket}
  end

  describe "support inbox" do
    test "lists tickets needing a reply and filters them", %{conn: conn, ticket: ticket} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture(["support"])) |> live(~p"/support")
      assert has_element?(view, "#tickets-#{ticket.id}", "Upload stuck")

      view |> form("#ticket-filters", tickets: %{category: "billing"}) |> render_change()
      refute has_element?(view, "#tickets-#{ticket.id}")
    end

    test "updates live when a ticket comes in", %{conn: conn, customer: customer} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture(["support"])) |> live(~p"/support")

      {:ok, new} =
        Support.create_ticket(Scope.for_user(customer), %{
          "category" => "other",
          "subject" => "Another",
          "body" => "x"
        })

      assert render(view) =~ "Another"
      assert has_element?(view, "#tickets-#{new.id}")
    end

    test "replies, adds a note, assigns and solves", %{
      conn: conn,
      ticket: ticket,
      customer: customer
    } do
      staff = staff_fixture(["support"])
      {:ok, view, _html} = conn |> log_in_staff(staff) |> live(~p"/support/#{ticket.number}")
      assert has_element?(view, "#ticket-customer", customer.email)

      view
      |> form("#reply-form", reply: %{body: "Try a smaller photo.", internal: "false"})
      |> render_submit()

      assert has_element?(view, "#thread", "Try a smaller photo.")

      view |> form("#reply-form", reply: %{internal: "true"}) |> render_change()

      view
      |> form("#reply-form", reply: %{body: "Probably HEIC", internal: "true"})
      |> render_submit()

      assert has_element?(view, "#thread", "Internal note")

      owner = Support.get_ticket!(Scope.for_user(customer), ticket.number)
      refute Enum.any?(owner.messages, &(&1.body == "Probably HEIC"))

      view |> form("#assign-form", %{assignee_id: staff.id}) |> render_change()
      assert Repo.reload!(ticket).assignee_id == staff.id

      view |> element("#mark-solved") |> render_click()
      assert Repo.reload!(ticket).status == "resolved"
    end

    test "inserts a canned reply into the box", %{conn: conn, ticket: ticket} do
      admin = staff_scope_fixture()

      {:ok, reply} =
        SupportAdmin.save_reply(admin, %Keepsakes.Support.CannedReply{}, %{
          "title" => "HEIC",
          "body" => "Please send a JPG."
        })

      {:ok, view, _html} = conn |> log_in_staff(admin.user) |> live(~p"/support/#{ticket.number}")

      html =
        view
        |> form("#reply-form", reply: %{body: "Hi!", canned: reply.id})
        |> render_change(%{"_target" => ["reply", "canned"]})

      assert html =~ "Hi!\n\nPlease send a JPG."
    end

    test "Support without support.assign sees but can't assign", %{conn: conn, ticket: ticket} do
      {:ok, role} =
        Keepsakes.Staff.create_role(staff_scope_fixture(), %{
          "name" => "Helpers",
          "permissions" => ["support.view", "support.reply"]
        })

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture([role.key])) |> live(~p"/support/#{ticket.number}")

      assert has_element?(view, "#reply-form")
      refute has_element?(view, "#assign-form")
    end

    test "canned replies page", %{conn: conn} do
      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture(["support"])) |> live(~p"/support/replies")

      view |> element("#new-reply") |> render_click()

      view
      |> form("#canned-reply-form", canned_reply: %{title: "Thanks", body: "Thanks for waiting."})
      |> render_submit()

      assert render(view) =~ "Thanks for waiting."
    end

    test "Finance can't open support", %{conn: conn} do
      conn = log_in_staff(conn, staff_fixture(["finance"]))
      assert_error_sent 403, fn -> get(conn, ~p"/support") end
    end
  end

  describe "templates" do
    test "edits a theme with a live preview", %{conn: conn} do
      default = Keepsakes.Templates.system_default()

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/templates/#{default.id}")

      view |> form("#template-form", template: %{theme: %{page: "#102030"}}) |> render_change()
      assert has_element?(view, ~s(#template-preview[style*="#102030"]))

      view |> form("#template-form", template: %{theme: %{page: "#102030"}}) |> render_submit()
      assert_redirect(view, ~p"/templates")
      assert Repo.reload!(default).theme["page"] == "#102030"
    end

    test "won't hide the default", %{conn: conn} do
      default = Keepsakes.Templates.system_default()

      {:ok, view, _html} =
        conn |> log_in_staff(staff_fixture()) |> live(~p"/templates/#{default.id}")

      view |> form("#template-form", template: %{active: "false"}) |> render_submit()
      assert has_element?(view, "#active-error")
    end
  end

  describe "settings" do
    test "saves and resets", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/settings")

      view |> form("#settings-form", settings: %{trial_days: "45"}) |> render_submit()
      assert Settings.get(:trial_days) == 45

      view |> element("#reset-trial_days") |> render_click()
      assert Settings.get(:trial_days) == 60
    end

    test "offers the bypass link while maintenance is on", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/settings")
      refute has_element?(view, "#maintenance-bypass")

      view |> form("#settings-form", settings: %{maintenance_mode: "true"}) |> render_submit()
      assert has_element?(view, "#maintenance-bypass[href*='/maintenance/bypass?token=']")
    end
  end

  describe "feature flags" do
    test "turns a flag on for one customer", %{conn: conn, customer: customer} do
      {:ok, view, _html} = conn |> log_in_staff(staff_fixture()) |> live(~p"/flags")

      view |> element("#flag-guest_uploads-chosen") |> render_click()

      view
      |> form("#flag-guest_uploads-add", %{flag: "guest_uploads", email: customer.email})
      |> render_submit()

      assert has_element?(view, "#flag-guest_uploads-user-#{customer.id}")
      assert Flags.enabled?(:guest_uploads, customer)
    end
  end

  test "sidebar shows the new sections by permission", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_staff(staff_fixture(["support"])) |> live(~p"/")
    assert has_element?(view, "#admin-nav-support")
    refute has_element?(view, "#admin-nav-templates")
    refute has_element?(view, "#admin-nav-settings")
    refute has_element?(view, "#admin-nav-flags")
  end
end
