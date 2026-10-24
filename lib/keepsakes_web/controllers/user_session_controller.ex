defmodule KeepsakesWeb.UserSessionController do
  use KeepsakesWeb, :controller

  alias Keepsakes.Accounts
  alias KeepsakesWeb.{AuthThrottle, UserAuth}

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Welcome to Keepsake! We've emailed you a link to confirm your address.")
  end

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Your email is confirmed.")
  end

  def create(conn, %{"_action" => "reset"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings#password")
    |> create(params, "You're signed in. Choose a new password below.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login (sign-in, confirmation and password-reset links)
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    current_user = conn.assigns.current_scope && conn.assigns.current_scope.user

    case Accounts.login_user_by_magic_link(token, current_user) do
      {:ok, {%{hashed_password: nil} = user, tokens_to_disconnect}} ->
        # No password on the account (it was claimed via the emailed link), so
        # send them to set one.
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_session(:user_return_to, ~p"/users/settings#password")
        |> put_flash(
          :info,
          "Your email is confirmed. Set a password to finish securing your account."
        )
        |> UserAuth.log_in_user(user, user_params)

      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    with :ok <- AuthThrottle.login(AuthThrottle.client_ip(conn), email),
         %Accounts.User{} = user <- Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      {:error, {:rate_limited, _} = reason} ->
        conn
        |> put_flash(:error, AuthThrottle.message(reason))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")

      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
