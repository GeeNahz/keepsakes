defmodule Keepsakes.SupportTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.{Storage, Support}
  alias Keepsakes.Support.{Message, Ticket}

  setup do
    scope = user_scope_fixture()
    assert_email_sent(subject: "Confirm your Keepsake account")
    %{scope: scope}
  end

  defp ticket_fixture(scope, attrs \\ %{}, files \\ []) do
    {:ok, ticket} =
      Support.create_ticket(
        scope,
        Enum.into(attrs, %{
          "category" => "technical",
          "subject" => "Upload stuck",
          "body" => "It spins."
        }),
        files
      )

    ticket
  end

  defp staff, do: user_fixture()

  describe "opening a ticket" do
    test "numbers it, keeps the message and files, and confirms by email", %{scope: scope} do
      path = Path.join(System.tmp_dir!(), "ks-shot-#{System.unique_integer([:positive])}.png")
      File.write!(path, "png-bytes")

      ticket =
        ticket_fixture(scope, %{}, [
          %{path: path, filename: "screen shot.png", content_type: "image/png", bytes: 9}
        ])

      assert ticket.number =~ ~r/^KS-T-\d{4,}$/
      assert {ticket.status, ticket.priority} == {"open", "normal"}
      assert_email_sent(subject: "We've got your message (#{ticket.number})")

      ticket = Support.get_ticket!(scope, ticket.number)

      assert [%Message{author_type: "user", body: "It spins.", attachments: [attachment]}] =
               ticket.messages

      assert attachment.filename == "screen shot.png"
      assert {:ok, "png-bytes"} = Storage.get(attachment.storage_key)
    end

    test "abuse reports start at high priority", %{scope: scope} do
      assert ticket_fixture(scope, %{"category" => "abuse"}).priority == "high"
    end

    test "needs a category, subject and message", %{scope: scope} do
      assert {:error, changeset} = Support.create_ticket(scope, %{"category" => "nope"})
      assert %{category: [_], subject: [_], body: [_]} = errors_on(changeset)
    end

    test "only the owner can read it", %{scope: scope} do
      ticket = ticket_fixture(scope)

      assert_raise Ecto.NoResultsError, fn ->
        Support.get_ticket!(user_scope_fixture(), ticket.number)
      end
    end
  end

  describe "the conversation" do
    test "status follows who wrote last; staff notes stay hidden", %{scope: scope} do
      staff = staff()
      assert_email_sent(subject: "Confirm your Keepsake account")
      ticket = ticket_fixture(scope)
      assert_email_sent(subject: "We've got your message (#{ticket.number})")

      {:ok, _} = Support.staff_reply(ticket, staff, "Checking our logs", internal: true)
      assert Repo.reload!(ticket).status == "open"
      refute_email_sent()

      {:ok, _} = Support.staff_reply(ticket, staff, "Try refreshing?")
      ticket = Repo.reload!(ticket)
      assert ticket.status == "awaiting_user"
      assert ticket.first_response_at
      assert_email_sent(subject: "Re: Upload stuck (#{ticket.number})")

      {:ok, _} = Support.reply(scope, ticket, "Still stuck", [])
      assert Repo.reload!(ticket).status == "awaiting_staff"

      bodies =
        scope
        |> Support.get_ticket!(ticket.number)
        |> Map.fetch!(:messages)
        |> Enum.map(& &1.body)

      assert bodies == ["It spins.", "Try refreshing?", "Still stuck"]
    end

    test "solved, reopened by writing, rated, then closed after 7 days", %{scope: scope} do
      ticket = ticket_fixture(scope)
      {:ok, ticket} = Support.resolve(scope, ticket)
      assert ticket.status == "resolved"

      {:ok, _} = Support.reply(scope, ticket, "Actually, one more thing", [])
      ticket = Repo.reload!(ticket)
      assert {ticket.status, ticket.resolved_at} == {"awaiting_staff", nil}

      {:ok, ticket} = Support.resolve(scope, ticket)
      {:ok, ticket} = Support.rate(scope, ticket, 5, " Quick and kind ")
      assert {ticket.rating, ticket.rating_comment} == {5, "Quick and kind"}

      assert Support.close_resolved() == 0
      assert Support.close_resolved(DateTime.add(ticket.resolved_at, 8, :day)) == 1
      ticket = Repo.reload!(ticket)
      assert ticket.status == "closed"
      assert {:error, :closed} = Support.reply(scope, ticket, "Hello?", [])
    end

    test "an empty reply is refused", %{scope: scope} do
      assert {:error, :empty} = Support.reply(scope, ticket_fixture(scope), "   ", [])
    end
  end

  describe "guest reports" do
    test "create a high-priority abuse ticket for the album", %{scope: scope} do
      album = album_fixture(scope, name: "Our Little One")
      link = share_link_fixture(scope, album)

      assert {:error, :invalid} = Support.report_album(link, %{"reason" => "made up"})

      assert {:ok, %Ticket{} = ticket} =
               Support.report_album(link, %{
                 "reason" => "Copyright",
                 "details" => "Photo 3 is mine",
                 "email" => "guest@example.com"
               })

      assert {ticket.category, ticket.priority, ticket.album_id} == {"abuse", "high", album.id}
      assert is_nil(ticket.user_id)
      assert_email_sent(subject: "Thanks for your report (#{ticket.number})")

      [message] = Repo.all(from m in Message, where: m.ticket_id == ^ticket.id)
      assert message.body =~ "Copyright"
      assert message.body =~ "Photo 3 is mine"
    end
  end

  describe "the support inbox" do
    setup do
      Application.put_env(:keepsakes, :support_inbox, "support@example.com")
      on_exit(fn -> Application.delete_env(:keepsakes, :support_inbox) end)
    end

    # Not async-safe in general, but only this test reads the inbox setting
    test "hears about new tickets", %{scope: scope} do
      ticket = ticket_fixture(scope)
      assert_email_sent(subject: "We've got your message (#{ticket.number})")

      assert_email_sent(fn email ->
        assert email.to == [{"", "support@example.com"}]
        assert email.subject == "[normal] #{ticket.number}: Upload stuck"
      end)
    end
  end
end
