defmodule KeepsakesWeb.LoginStepController do
  @moduledoc """
  The step after a correct password or sign-in link
  (`UserAuth.log_in_or_continue/3`):

    * `/auth/two-step` - enter the code from the authenticator app (or a
      recovery code); 6 tries per 15 minutes
    * `/auth/restore` - an account paused for deletion can be restored
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.TwoStep
  alias KeepsakesWeb.{AuthThrottle, UserAuth}

  plug :require_pending_user

  def two_step(conn, _params), do: render(conn, :two_step, error: nil)

  def verify_two_step(conn, %{"code" => code}) do
    user = conn.assigns.pending_user

    with :ok <- AuthThrottle.two_step(user.id),
         {:ok, user} <- TwoStep.verify(user, code) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.finish_pending_login(user)
    else
      {:error, {:rate_limited, _} = reason} ->
        render(conn, :two_step, error: AuthThrottle.message(reason))

      {:error, :invalid_code} ->
        render(conn, :two_step, error: "That code didn't work. Try the newest one from your app.")
    end
  end

  def restore(conn, _params) do
    render(conn, :restore, delete_on: Accounts.deletion_date(conn.assigns.pending_user))
  end

  def do_restore(conn, _params) do
    {:ok, user} = Accounts.restore_account(conn.assigns.pending_user)
    conn = put_flash(conn, :info, "Welcome back! Your account is restored.")

    # Restoring doesn't skip two-step login
    if TwoStep.enabled?(user),
      do: redirect(conn, to: ~p"/auth/two-step"),
      else: UserAuth.finish_pending_login(conn, user)
  end

  def cancel(conn, _params) do
    conn
    |> UserAuth.clear_pending_login()
    |> redirect(to: ~p"/auth/log-in")
  end

  defp require_pending_user(conn, _opts) do
    case UserAuth.pending_user(conn) do
      nil ->
        conn
        |> put_flash(:error, "Please log in again.")
        |> redirect(to: ~p"/auth/log-in")
        |> halt()

      user ->
        assign(conn, :pending_user, user)
    end
  end
end
