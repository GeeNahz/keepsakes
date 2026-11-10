defmodule Keepsakes.Domains.Notifier do
  @moduledoc "Emails about a customer's own domain: connected, or not working."
  alias Keepsakes.Accounts.User
  alias Keepsakes.Mailer

  defp deliver(%User{} = user, opts) do
    email =
      [
        to: {User.full_name(user), user.email},
        greeting: "Hi #{user.first_name},",
        action: {"Domain settings", KeepsakesWeb.Endpoint.url() <> "/app/settings/domains"}
      ]
      |> Keyword.merge(opts)
      |> Mailer.build()

    with {:ok, _} <- Mailer.deliver(email), do: {:ok, email}
  end

  @doc "The domain checked out; their site is live there."
  def deliver_verified(user, domain) do
    deliver(user,
      subject: "#{domain.hostname} is connected to Keepsake",
      heading: "Your domain is connected",
      paragraphs: [
        "#{domain.hostname} now opens your Keepsake site. Choose which albums appear there in " <>
          "your domain settings; each still needs its access code.",
        "It can take a few minutes for the secure (https) version to be ready the first time."
      ]
    )
  end

  @doc "The records weren't found in time, or stopped being right."
  def deliver_failed(user, domain) do
    deliver(user,
      subject: "#{domain.hostname} isn't connected",
      heading: "We couldn't connect your domain",
      paragraphs: [
        "We checked #{domain.hostname} but couldn't confirm it: #{domain.last_error || "the DNS records weren't found"}.",
        "Check the records in your domain settings, then press Check now. Your albums still open at their usual Keepsake links."
      ]
    )
  end
end
