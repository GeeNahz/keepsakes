defmodule Keepsakes.Albums.Notifier do
  @moduledoc "Emails about albums: collaborator invitations."
  alias Keepsakes.Accounts.User
  alias Keepsakes.Albums.{Album, Member}
  alias Keepsakes.Mailer

  @doc "Invites `member.email` to `album`, with the link to accept."
  def deliver_invite(%Member{} = member, %Album{} = album, %User{} = owner, url) do
    can =
      case member.role do
        "editor" -> "add and edit photos"
        _ -> "see every photo"
      end

    email =
      Mailer.build(
        to: member.email,
        greeting: "Hi,",
        subject: "#{User.full_name(owner)} invited you to #{album.name}",
        heading: "Join #{album.name} on Keepsake",
        paragraphs: [
          "#{User.full_name(owner)} invited you to the album #{album.name}, where you can #{can}.",
          "Sign in, or create a free account, with #{member.email} to join. The link works for 14 days."
        ],
        action: {"Join the album", url},
        footnote: "Not expecting this? You can ignore this email."
      )

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
