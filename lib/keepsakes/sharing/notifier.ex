defmodule Keepsakes.Sharing.Notifier do
  @moduledoc "Emails about shared albums."
  alias Keepsakes.Accounts.User
  alias Keepsakes.Mailer

  @doc "The daily guest-activity email: `visits` is `[{album_name, opens}]`."
  def deliver_guest_digest(%User{} = user, visits) do
    total = visits |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    lines =
      for {album, opens} <- Enum.sort_by(visits, &(-elem(&1, 1))) do
        "#{album}: opened #{times(opens)}"
      end

    email =
      Mailer.build(
        to: {User.full_name(user), user.email},
        greeting: "Hi #{user.first_name},",
        subject: summary_subject(visits, total),
        heading: "Your albums had visitors",
        paragraphs: lines,
        action: {"See your albums", KeepsakesWeb.Endpoint.url() <> "/app/albums"},
        footnote: "You can turn these emails off in Settings → Notifications."
      )

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp summary_subject([{album, _}], total),
    do: "#{album} was opened #{times(total)} in the last day"

  defp summary_subject(visits, total),
    do: "Your #{length(visits)} albums were opened #{times(total)} in the last day"

  defp times(1), do: "once"
  defp times(2), do: "twice"
  defp times(n), do: "#{n} times"
end
