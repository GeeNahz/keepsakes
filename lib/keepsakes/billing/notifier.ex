defmodule Keepsakes.Billing.Notifier do
  @moduledoc "Emails about the trial, grace period and plan changes."
  alias Keepsakes.Accounts.User
  alias Keepsakes.Mailer

  defp deliver(%User{} = user, opts) do
    email =
      [
        to: {User.full_name(user), user.email},
        greeting: "Hi #{user.first_name},",
        action: {"See plans", billing_url()}
      ]
      |> Keyword.merge(opts)
      |> Mailer.build()

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp billing_url, do: KeepsakesWeb.Endpoint.url() <> "/billing"

  @doc "A week before the trial ends."
  def deliver_trial_ending(user, ends_at) do
    deliver(user,
      subject: "Your Keepsake trial ends on #{date(ends_at)}",
      heading: "Your free trial ends soon",
      paragraphs: [
        "Your free trial ends on #{date(ends_at)}. Choose a plan to keep every feature, " <>
          "or do nothing and move to the Free plan after a short grace period.",
        "Your albums and photos stay safe either way."
      ]
    )
  end

  @doc "The trial is over; full access continues until `grace_ends_at`."
  def deliver_grace_started(user, grace_ends_at) do
    deliver(user,
      subject: "Your Keepsake trial has ended",
      heading: "Your trial has ended",
      paragraphs: [
        "You still have every feature until #{date(grace_ends_at)}. After that your " <>
          "account moves to the Free plan.",
        "Nothing is deleted. If you're over the Free plan's limits, your albums stay as " <>
          "they are and guests can still view them; you just can't add more until you " <>
          "upgrade or make room."
      ]
    )
  end

  @doc "The grace period ran out and the account is now on Free."
  def deliver_moved_to_free(user) do
    deliver(user,
      subject: "Your Keepsake account is now on the Free plan",
      heading: "You're on the Free plan",
      paragraphs: [
        "Your account has moved to the Free plan. Everything you've added is still there, " <>
          "and your shared links keep working.",
        "Upgrade any time to get more storage, more albums and premium templates back."
      ]
    )
  end

  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B %Y")
end
