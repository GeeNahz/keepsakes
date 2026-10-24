defmodule Keepsakes.Accounts.UserNotifier do
  alias Keepsakes.Mailer
  alias Keepsakes.Accounts.User

  defp deliver(%User{} = user, opts) do
    email =
      [to: {User.full_name(user), user.email}, greeting: "Hi #{user.first_name},"]
      |> Keyword.merge(opts)
      |> Mailer.build()

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    # `user` already carries the new, unconfirmed address
    deliver(user,
      subject: "Confirm your new email address",
      heading: "Confirm your new email",
      paragraphs: ["Use the button below to make this your Keepsake sign-in email."],
      action: {"Confirm new email", url},
      footnote: "The link works for 7 days. If you didn't ask for this change, ignore this email."
    )
  end

  @doc """
  Deliver instructions to log in with a magic link, or to confirm the
  account when it is not confirmed yet.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  @doc """
  Deliver "reset your password" instructions.
  """
  def deliver_password_reset_instructions(user, url) do
    deliver(user,
      subject: "Reset your Keepsake password",
      heading: "Reset your password",
      paragraphs: ["Use the button below to sign in and choose a new password."],
      action: {"Choose a new password", url},
      footnote:
        "The link works once, for 15 minutes. If you didn't ask for this, you can ignore " <>
          "this email; your password hasn't changed."
    )
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user,
      subject: "Your Keepsake sign-in link",
      heading: "Sign in to Keepsake",
      paragraphs: ["Use the button below to sign in. No password needed."],
      action: {"Sign in", url},
      footnote:
        "The link works once, for 15 minutes. If you didn't ask for it, ignore this email."
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user,
      subject: "Confirm your Keepsake account",
      heading: "Confirm your email",
      paragraphs: [
        "Thanks for creating a Keepsake account. Confirm your email so we can reach you " <>
          "about your albums and your free trial."
      ],
      action: {"Confirm my email", url},
      footnote:
        "The link works for 15 minutes; you can request a new one from your account. " <>
          "If you didn't create an account, ignore this email."
    )
  end
end
