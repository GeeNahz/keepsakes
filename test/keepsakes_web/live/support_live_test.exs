defmodule KeepsakesWeb.SupportLiveTest do
  use KeepsakesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Support

  describe "Help" do
    setup :register_and_log_in_user

    test "opens a ticket with a file and lands on its page", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/app/help")
      assert has_element?(lv, "#no-tickets")

      file =
        file_input(lv, "#ticket-form", :files, [
          %{name: "screen.jpg", content: jpeg(), type: "image/jpeg"}
        ])

      render_upload(file, "screen.jpg", 50)
      # Send waits while a file is still uploading
      assert has_element?(lv, "#file-#{hd(file.entries)["ref"]} progress")
      assert has_element?(lv, "#send-ticket[disabled]", "Uploading…")
      render_upload(file, "screen.jpg", 50)
      refute has_element?(lv, "#send-ticket[disabled]")

      assert {:error, {:live_redirect, %{to: "/app/help/" <> number}}} =
               lv
               |> form("#ticket-form",
                 ticket: %{category: "billing", subject: "Charged twice", body: "Two receipts"}
               )
               |> render_submit()

      ticket = Support.get_ticket!(scope, number)
      assert [%{attachments: [%{filename: "screen.webp"}]}] = ticket.messages

      {:ok, lv, _html} = live(conn, ~p"/app/help")
      assert has_element?(lv, "#ticket-#{number}", "Charged twice")
    end

    test "shows what's missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/help")
      lv |> form("#ticket-form", ticket: %{subject: "", body: ""}) |> render_submit()
      assert render(lv) =~ "Please fill this in"
    end

    test "the thread updates live, takes replies, and can be solved and rated", %{
      conn: conn,
      scope: scope
    } do
      {:ok, ticket} =
        Support.create_ticket(scope, %{
          "category" => "technical",
          "subject" => "Slideshow",
          "body" => "It stops"
        })

      {:ok, lv, _html} = live(conn, ~p"/app/help/#{ticket.number}")
      assert has_element?(lv, "#ticket-subject", "Slideshow")

      {:ok, _} = Support.staff_reply(ticket, user_fixture(), "Which browser?")
      assert has_element?(lv, "#ticket-messages", "Which browser?")
      assert has_element?(lv, "#ticket-messages", "Keepsake support")

      lv |> form("#reply-form", body: "Chrome on Android") |> render_submit()
      assert has_element?(lv, "#ticket-messages", "Chrome on Android")

      lv |> element("#resolve-ticket") |> render_click()
      assert has_element?(lv, "#ticket-messages", "Marked as solved")
      assert has_element?(lv, "#reopen-ticket")

      lv |> form("#rating-form", rating: "4") |> render_submit()
      assert has_element?(lv, "#ticket-rating", "4 out of 5")
    end

    test "the account menu links to Help", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/albums")
      assert has_element?(lv, ~s(#user-menu-help[href="/app/help"]))
    end
  end

  describe "guest report" do
    setup do
      scope = user_scope_fixture()
      album = album_fixture(scope, name: "Our Little One")
      %{link: share_link_fixture(scope, album)}
    end

    test "is linked from the timeline and sends a report", %{conn: conn, link: link} do
      conn = init_test_session(conn, %{"guest_links" => %{link.id => link.code_version}})
      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}/timeline")
      assert has_element?(lv, ~s(#report-album[href="/a/#{link.slug}/report"]))

      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}/report")

      lv
      |> form("#report-form", reason: "Spam or a scam", details: "Not a real album")
      |> render_submit()

      assert has_element?(lv, "#report-sent")

      assert [ticket] = Keepsakes.Repo.all(Keepsakes.Support.Ticket)
      assert ticket.share_link_id == link.id
    end

    test "works without the code", %{conn: conn, link: link} do
      {:ok, lv, _html} = live(conn, ~p"/a/#{link.slug}/report")
      assert has_element?(lv, "#report-form")
    end
  end
end
