defmodule KeepsakesWeb.UserConfirmationController do
  use KeepsakesWeb, :controller

  alias Keepsakes.Accounts
  alias KeepsakesWeb.AuthThrottle

  @doc "Re-sends the confirmation email to the logged-in, unconfirmed user."
  def create(conn, _params) do
    user = conn.assigns.current_scope.user

    conn =
      cond do
        user.confirmed_at ->
          put_flash(conn, :info, "Your email is already confirmed.")

        match?({:error, _}, AuthThrottle.email_link(AuthThrottle.client_ip(conn), user.email)) ->
          put_flash(
            conn,
            :error,
            "We've sent a few already. Please check your inbox and spam folder."
          )

        true ->
          {:ok, _} = Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
          put_flash(conn, :info, "Sent! Check #{user.email} for the confirmation link.")
      end

    redirect(conn, to: ~p"/albums")
  end
end
