defmodule Keepsakes.MailerTest do
  use ExUnit.Case, async: true

  alias Keepsakes.Mailer

  test "build/1 makes a branded HTML part and a matching text part" do
    email =
      Mailer.build(
        to: {"Ada Lovelace", "ada@example.com"},
        subject: "Confirm your email",
        heading: "Confirm your email",
        greeting: "Hi Ada,",
        paragraphs: ["Thanks for joining <us>."],
        action: {"Confirm", "https://example.com/c/abc"},
        footnote: "Ignore this if it wasn't you."
      )

    assert email.from == Application.fetch_env!(:keepsakes, :mail_from)
    assert email.to == [{"Ada Lovelace", "ada@example.com"}]

    assert email.html_body =~ ~s(href="https://example.com/c/abc")
    # user-facing text is HTML-escaped
    assert email.html_body =~ "Thanks for joining &lt;us&gt;."

    assert email.text_body =~ "Hi Ada,"
    assert email.text_body =~ "Confirm:\nhttps://example.com/c/abc"
    assert email.text_body =~ "Ignore this if it wasn't you."
  end
end
