defmodule Keepsakes.Support.Notifier do
  @moduledoc """
  Support emails: to the customer (ticket received, support replied), to a
  guest who reported an album, and to the support inbox (`SUPPORT_INBOX`)
  for new tickets and customer replies until the admin portal exists.
  """
  alias Keepsakes.Accounts.User
  alias Keepsakes.Mailer

  defp deliver(to, greeting, opts) do
    email = [to: to, greeting: greeting] |> Keyword.merge(opts) |> Mailer.build()

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp ticket_url(ticket), do: KeepsakesWeb.Endpoint.url() <> "/app/help/#{ticket.number}"

  @doc "The owner opened a ticket."
  def deliver_ticket_received(%User{} = user, ticket) do
    deliver({User.full_name(user), user.email}, "Hi #{user.first_name},",
      subject: "We've got your message (#{ticket.number})",
      heading: "Thanks, we're on it",
      paragraphs: [
        "We've received your message, \"#{ticket.subject}\", and will reply as soon as we can.",
        "You can add details or photos to the conversation any time."
      ],
      action: {"View your ticket", ticket_url(ticket)}
    )
  end

  @doc "Support replied on the owner's ticket."
  def deliver_staff_replied(%User{} = user, ticket, message) do
    deliver({User.full_name(user), user.email}, "Hi #{user.first_name},",
      subject: "Re: #{ticket.subject} (#{ticket.number})",
      heading: "Support replied",
      paragraphs: [String.slice(message.body, 0, 1200)],
      action: {"Reply", ticket_url(ticket)},
      footnote: "Reply from the link above so everything stays in one place."
    )
  end

  @doc "A guest who reported an album and left an email."
  def deliver_report_received(email, ticket) do
    deliver(email, "Hello,",
      subject: "Thanks for your report (#{ticket.number})",
      heading: "Thanks for telling us",
      paragraphs: [
        "We've received your report and will review the album. If we need anything else " <>
          "we'll reply to this address."
      ]
    )
  end

  @doc "New ticket or customer reply, to the support inbox when one is configured."
  def alert_staff(ticket, message, from) do
    case Application.get_env(:keepsakes, :support_inbox) do
      inbox when is_binary(inbox) and inbox != "" ->
        deliver(inbox, "Hello,",
          subject: "[#{ticket.priority}] #{ticket.number}: #{ticket.subject}",
          heading: "#{category(ticket.category)} · #{from || "anonymous guest"}",
          paragraphs: [String.slice(message.body, 0, 3000)],
          footnote: "Reply from the admin portal once it's available (Stage 7)."
        )

      _ ->
        :ok
    end
  end

  defp category("billing"), do: "Billing"
  defp category("technical"), do: "Technical"
  defp category("account"), do: "Account"
  defp category("abuse"), do: "Abuse report"
  defp category(_), do: "Other"
end
