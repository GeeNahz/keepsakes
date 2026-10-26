defmodule Keepsakes.Billing.Notifier do
  @moduledoc "Emails about the trial, payments, renewals and plan changes."
  alias Keepsakes.Accounts.User
  alias Keepsakes.Billing.{PaymentMethod, Price}
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

  defp billing_url, do: KeepsakesWeb.Endpoint.url() <> "/app/settings/billing"

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

  @doc "Staff added days to the free trial (Keepsakes.Customers)."
  def deliver_trial_extended(user, ends_at) do
    deliver(user,
      subject: "Your Keepsake trial now runs until #{date(ends_at)}",
      heading: "More time on your free trial",
      paragraphs: [
        "We've extended your free trial. You have every feature until #{date(ends_at)}.",
        "Choose a plan any time to keep them after that."
      ]
    )
  end

  @doc "Staff gave a paid plan free of charge until `ends_at` (Keepsakes.Customers)."
  def deliver_plan_given(user, plan, ends_at) do
    deliver(user,
      subject: "You've been given Keepsake #{plan.name}",
      heading: "Enjoy #{plan.name}, on us",
      paragraphs: [
        "The Keepsake team has given you the #{plan.name} plan until #{date(ends_at)}, " <>
          "free of charge. No card is needed and you won't be charged.",
        "After that your account moves to the Free plan unless you choose a paid plan. " <>
          "Nothing you've added is deleted."
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

  @doc "A paid invoice: what was charged, for which plan and period."
  def deliver_receipt(user, invoice, payment_method) do
    lines =
      [
        "Plan: #{invoice.plan.name} (#{interval(invoice.price.interval)})",
        "Period: #{date(invoice.period_start)} to #{date(invoice.period_end)}",
        invoice.discount_minor > 0 &&
          "#{invoice.discount_label || "Discount"}: −#{Price.format(invoice.currency, invoice.discount_minor)}",
        invoice.credit_minor > 0 &&
          "Credit for unused days: −#{Price.format(invoice.currency, invoice.credit_minor)}",
        "Paid: #{Price.format(invoice.currency, invoice.amount_minor)}" <>
          if(payment_method, do: " with #{PaymentMethod.label(payment_method)}", else: "")
      ]
      |> Enum.filter(& &1)

    deliver(user,
      subject: "Your Keepsake receipt #{invoice.number}",
      heading: "Thank you, payment received",
      paragraphs: lines,
      action:
        {"View receipt",
         KeepsakesWeb.Endpoint.url() <> "/app/settings/billing/invoices/#{invoice.id}"},
      footnote:
        "Your plan renews automatically on #{date(invoice.period_end)}. " <>
          "You can cancel any time from Plans & billing."
    )
  end

  @doc "A renewal charge failed; we'll retry on `next_retry_at`."
  def deliver_payment_failed(user, next_retry_at) do
    deliver(user,
      subject: "We couldn't renew your Keepsake plan",
      heading: "Your renewal payment didn't go through",
      paragraphs: [
        "We couldn't charge your card for your Keepsake plan. You still have every " <>
          "feature while we sort it out, and we'll try again on #{date(next_retry_at)}.",
        "To fix it now, pay with another card from Plans & billing."
      ],
      action: {"Pay now", billing_url()}
    )
  end

  @doc "Every retry failed; full access continues until `grace_ends_at`."
  def deliver_renewal_grace(user, grace_ends_at) do
    deliver(user,
      subject: "Action needed: your Keepsake plan is about to end",
      heading: "We still couldn't renew your plan",
      paragraphs: [
        "After several tries we couldn't charge your card. Your plan's features stay " <>
          "on until #{date(grace_ends_at)}; after that your account moves to the Free plan.",
        "Nothing is deleted. Pay with another card any time to keep your plan."
      ],
      action: {"Pay now", billing_url()}
    )
  end

  @doc "A paid plan renews in a few days (billing reminders on)."
  def deliver_renewal_soon(user, price, renews_on) do
    deliver(user,
      subject: "Your Keepsake plan renews on #{date(renews_on)}",
      heading: "Your plan renews soon",
      paragraphs: [
        "Your #{price.plan.name} plan renews on #{date(renews_on)} for " <>
          "#{Price.format(price)} (before any discount), charged to your saved card.",
        "Nothing to do if you'd like to keep it. You can change or cancel your plan any time " <>
          "before then."
      ],
      footnote: "You can turn these reminders off in Settings → Notifications."
    )
  end

  @doc "Someone the user invited made their first payment: a free month."
  def deliver_referral_reward(user, referred, reward) do
    detail =
      case reward do
        {:extended, until} ->
          "We've added a month to your plan, so it now renews on #{date(until)}."

        :banked ->
          "It's saved for you and will be added to your first paid period when you choose a plan."
      end

    deliver(user,
      subject: "You earned a free month of Keepsake",
      heading: "Thanks for spreading the word",
      paragraphs: [
        "#{referred.first_name} joined Keepsake with your invite link and just chose a plan, " <>
          "so you've earned a free month.",
        detail
      ]
    )
  end

  defp interval("month"), do: "monthly"
  defp interval("year"), do: "yearly"

  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B %Y")
end
