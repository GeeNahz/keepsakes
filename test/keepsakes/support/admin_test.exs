defmodule Keepsakes.Support.AdminTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, Support}
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Staff.Forbidden
  alias Keepsakes.Support.{Admin, Ticket}

  setup do
    admin = staff_scope_fixture()
    customer = user_fixture()
    flush_emails()

    {:ok, ticket} =
      Support.create_ticket(Scope.for_user(customer), %{
        "category" => "billing",
        "subject" => "Charged twice",
        "body" => "Please help"
      })

    flush_emails()
    %{admin: admin, customer: customer, ticket: ticket}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp at(ticket, fields), do: ticket |> Ecto.Changeset.change(fields) |> Repo.update!()

  describe "SLA" do
    test "first-reply targets by priority", %{ticket: ticket} do
      now = DateTime.utc_now(:second)
      assert Admin.sla_hours("urgent") == 4
      assert Admin.sla_hours("normal") == 24

      assert Admin.sla(%{ticket | inserted_at: now}, now) == :on_track
      assert Admin.sla(%{ticket | inserted_at: DateTime.add(now, -20, :hour)}, now) == :due_soon
      assert Admin.sla(%{ticket | inserted_at: DateTime.add(now, -25, :hour)}, now) == :overdue

      assert Admin.sla(
               %{ticket | priority: "urgent", inserted_at: DateTime.add(now, -5, :hour)},
               now
             ) == :overdue

      assert Admin.sla(%{ticket | first_response_at: now}, now) == :replied
      assert Admin.sla(%{ticket | status: "closed"}, now) == :none
    end
  end

  describe "list/3" do
    test "needs-reply view, filters and search", %{
      admin: admin,
      ticket: ticket,
      customer: customer
    } do
      numbers = fn filters -> admin |> Admin.list(filters) |> elem(0) |> Enum.map(& &1.number) end

      assert ticket.number in numbers.(%{})
      assert ticket.number in numbers.(%{"q" => customer.email})
      assert ticket.number in numbers.(%{"q" => "twice"})
      refute ticket.number in numbers.(%{"category" => "abuse"})
      assert ticket.number in numbers.(%{"assignee" => "unassigned"})
      refute ticket.number in numbers.(%{"assignee" => "me"})

      at(ticket, status: "awaiting_user")
      refute ticket.number in numbers.(%{})
      assert ticket.number in numbers.(%{"view" => "all"})
    end

    test "unanswered tickets come first by when their reply is due", %{
      admin: admin,
      customer: customer
    } do
      now = DateTime.utc_now(:second)
      scope = Scope.for_user(customer)

      make = fn subject, priority, hours_ago ->
        {:ok, t} =
          Support.create_ticket(scope, %{
            "category" => "other",
            "subject" => subject,
            "body" => "x"
          })

        at(t, priority: priority, inserted_at: DateTime.add(now, -hours_ago, :hour))
      end

      _normal = make.("normal fresh", "normal", 0)
      _urgent = make.("urgent fresh", "urgent", 0)
      _old_normal = make.("normal old", "normal", 23)

      subjects =
        admin |> Admin.list(%{"category" => "other"}) |> elem(0) |> Enum.map(& &1.subject)

      assert subjects == ["normal old", "urgent fresh", "normal fresh"]
    end

    test "needs support.view" do
      assert_raise Forbidden, fn -> Admin.list(staff_scope_fixture(["finance"])) end
    end
  end

  describe "replies and notes" do
    test "a reply reaches the customer; a note doesn't", %{
      admin: admin,
      customer: customer,
      ticket: ticket
    } do
      assert {:ok, _} = Admin.reply(admin, ticket, "We've refunded the second charge.")
      assert_email_sent(to: [{Keepsakes.Accounts.User.full_name(customer), customer.email}])

      assert {:ok, _} =
               Admin.reply(admin, Repo.reload!(ticket), "Checked Flutterwave first", true)

      refute_email_sent()

      owner_view = Support.get_ticket!(Scope.for_user(customer), ticket.number)
      bodies = Enum.map(owner_view.messages, & &1.body)
      assert "We've refunded the second charge." in bodies
      refute "Checked Flutterwave first" in bodies

      staff_view = Admin.get!(admin, ticket.number)

      assert Enum.any?(
               staff_view.messages,
               &(&1.internal and &1.body == "Checked Flutterwave first")
             )

      assert staff_view.status == "awaiting_user"
      assert staff_view.first_response_at

      actions =
        admin |> Audit.list(%{"action" => "ticket."}) |> Enum.map(& &1.action) |> Enum.sort()

      assert actions == ["ticket.noted", "ticket.replied"]
    end

    test "empty replies and replies to closed tickets are refused", %{
      admin: admin,
      ticket: ticket
    } do
      assert {:error, :empty} = Admin.reply(admin, ticket, "  ")
      closed = at(ticket, status: "closed")
      assert {:error, :closed} = Admin.reply(admin, closed, "Hello")
      assert {:ok, _} = Admin.reply(admin, closed, "Note on a closed ticket", true)
    end

    test "needs support.reply", %{ticket: ticket} do
      viewer =
        Keepsakes.Staff.create_role(staff_scope_fixture(), %{
          "name" => "Readers",
          "permissions" => ["support.view"]
        })
        |> elem(1)
        |> then(&staff_scope_fixture([&1.key]))

      assert_raise Forbidden, fn -> Admin.reply(viewer, ticket, "Hi") end
    end
  end

  describe "assignment, priority and status" do
    test "assigns to staff only, and changes priority", %{
      admin: admin,
      ticket: ticket,
      customer: customer
    } do
      support = staff_fixture(["support"])
      assert {:ok, t} = Admin.assign(admin, ticket, support.id)
      assert t.assignee_id == support.id
      assert {:error, :not_staff} = Admin.assign(admin, t, customer.id)
      assert {:ok, t} = Admin.assign(admin, t, "")
      assert t.assignee_id == nil

      assert {:ok, t} = Admin.set_priority(admin, t, "urgent")
      assert t.priority == "urgent"
      assert {:error, :invalid} = Admin.set_priority(admin, t, "whenever")
    end

    test "solve, reopen and close add a line to the thread", %{admin: admin, ticket: ticket} do
      assert {:ok, t} = Admin.set_status(admin, ticket, "resolved")
      assert t.status == "resolved"
      assert {:ok, t} = Admin.set_status(admin, t, "awaiting_staff")
      assert {:ok, t} = Admin.set_status(admin, t, "closed")
      assert {:error, :invalid} = Admin.set_status(admin, t, "closed")

      lines =
        admin
        |> Admin.get!(ticket.number)
        |> Map.get(:messages)
        |> Enum.filter(&(&1.author_type == "system"))

      assert Enum.map(lines, & &1.body) == [
               "Marked as solved by support",
               "Reopened by support",
               "Closed by support"
             ]
    end

    test "changes reach open pages", %{admin: admin, ticket: ticket} do
      Support.subscribe_inbox()
      id = ticket.id
      {:ok, _} = Admin.set_priority(admin, ticket, "high")
      assert_receive {:ticket_updated, ^id}
    end
  end

  describe "canned replies" do
    test "create, edit and delete", %{admin: admin} do
      {:ok, reply} =
        Admin.save_reply(admin, %Keepsakes.Support.CannedReply{}, %{
          "title" => "Refund sent",
          "body" => "We've refunded you."
        })

      assert {:error, changeset} =
               Admin.save_reply(admin, %Keepsakes.Support.CannedReply{}, %{
                 "title" => "Refund sent",
                 "body" => "x"
               })

      assert errors_on(changeset)[:title]
      {:ok, reply} = Admin.save_reply(admin, reply, %{"body" => "Refunded today."})
      assert [%{body: "Refunded today."}] = Admin.list_replies(admin)
      {:ok, _} = Admin.delete_reply(admin, reply)
      assert Admin.list_replies(admin) == []
    end
  end

  test "new tickets reach the inbox live", %{customer: customer} do
    Support.subscribe_inbox()

    {:ok, %Ticket{id: id}} =
      Support.create_ticket(Scope.for_user(customer), %{
        "category" => "other",
        "subject" => "Hi",
        "body" => "x"
      })

    assert_receive {:ticket_updated, ^id}
  end
end
