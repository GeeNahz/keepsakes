defmodule KeepsakesWeb.InviteController do
  @moduledoc """
  `/invites/:token`: a collaborator invitation from the email.

  Opening the link never joins by itself (mail scanners open links too):
  the page shows what the invitation is and a Join button (POST). Someone
  not signed in is sent to sign in or sign up and comes back here
  (`:user_return_to`).
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Accounts.User
  alias Keepsakes.Albums.Members

  def show(conn, %{"token" => token}) do
    invite = Members.get_invite(token)
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    conn =
      if invite && is_nil(user),
        do: put_session(conn, :user_return_to, ~p"/invites/#{token}"),
        else: conn

    render(conn, :show,
      page_title: "Album invitation",
      invite: invite,
      token: token,
      state: state(invite, user),
      owner_name: invite && User.full_name(invite.album.user)
    )
  end

  def accept(conn, %{"token" => token}) do
    case conn.assigns.current_scope do
      %{user: %User{}} = scope ->
        case Members.accept(scope, token) do
          {:ok, album} ->
            conn
            |> put_flash(:info, "You joined #{album.name}.")
            |> redirect(to: ~p"/app/shared/#{album.id}")

          {:error, {:wrong_account, email}} ->
            conn
            |> put_flash(:error, "This invitation is for #{email}.")
            |> redirect(to: ~p"/invites/#{token}")

          {:error, :invalid} ->
            conn
            |> put_flash(:error, "This invitation has expired or was already used.")
            |> redirect(to: ~p"/invites/#{token}")
        end

      _ ->
        conn
        |> put_session(:user_return_to, ~p"/invites/#{token}")
        |> redirect(to: ~p"/auth/log-in")
    end
  end

  defp state(nil, _user), do: :invalid
  defp state(_invite, nil), do: :signed_out

  defp state(invite, %User{email: email}),
    do: if(String.downcase(email) == invite.email, do: :ready, else: :wrong_account)
end
