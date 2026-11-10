defmodule KeepsakesWeb.Admin.SessionController do
  @moduledoc """
  Admin portal sign-in on the admin host, with the account's own email
  and password. Staff who have two-step login on then enter a code.

  With `:require_staff_two_step` (`REQUIRE_STAFF_TWO_STEP=true`, meant for
  production) staff without it set it up here first (QR code, then their
  recovery codes, shown once); otherwise they go straight in.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.{Accounts, Staff}
  alias Keepsakes.Accounts.TwoStep
  alias KeepsakesWeb.Admin.Auth
  alias KeepsakesWeb.AuthThrottle

  plug :put_layout, html: false
  plug :put_page_title
  plug :require_pending when action in [:code, :verify, :setup, :enable, :finish]

  def new(conn, _params), do: render(conn, :new, error: nil, email: "")

  def create(conn, %{"email" => email, "password" => password}) do
    with :ok <- AuthThrottle.login(AuthThrottle.client_ip(conn), email),
         %Accounts.User{} = user <- Accounts.get_user_by_email_and_password(email, password),
         true <- Staff.staff?(user) do
      cond do
        TwoStep.enabled?(user) -> conn |> Auth.park(user) |> redirect(to: ~p"/two-step")
        two_step_required?() -> conn |> Auth.park(user) |> redirect(to: ~p"/two-step/setup")
        true -> Auth.log_in_staff(conn, user)
      end
    else
      {:error, {:rate_limited, _} = reason} ->
        render(conn, :new, error: AuthThrottle.message(reason), email: email)

      # Same message for a wrong password and for a customer who isn't staff
      _ ->
        render(conn, :new,
          error: "That email and password don't open the admin portal.",
          email: email
        )
    end
  end

  def code(conn, _params), do: render(conn, :code, error: nil)

  def verify(conn, %{"code" => code}) do
    user = conn.assigns.pending_user

    with :ok <- AuthThrottle.two_step(user.id),
         {:ok, user} <- TwoStep.verify(user, code) do
      Auth.log_in_staff(conn, user)
    else
      {:error, {:rate_limited, _} = reason} ->
        render(conn, :code, error: AuthThrottle.message(reason))

      {:error, :invalid_code} ->
        render(conn, :code, error: "That code didn't work. Try the newest one.")
    end
  end

  # When two-step login is required: set it up before getting in
  def setup(conn, _params) do
    user = conn.assigns.pending_user
    secret = get_session(conn, :staff_totp_secret) || TwoStep.new_secret()

    conn
    |> put_session(:staff_totp_secret, secret)
    |> render(:setup,
      qr: TwoStep.qr_svg(user, secret),
      key: TwoStep.manual_key(secret),
      error: nil
    )
  end

  def enable(conn, %{"code" => code}) do
    user = conn.assigns.pending_user
    secret = get_session(conn, :staff_totp_secret)

    case secret && TwoStep.enable(user, secret, code) do
      {:ok, _user, codes} ->
        conn
        |> delete_session(:staff_totp_secret)
        |> render(:recovery, codes: codes)

      _ ->
        render(conn, :setup,
          qr: TwoStep.qr_svg(user, secret),
          key: TwoStep.manual_key(secret),
          error: "That code didn't match. Try the newest one."
        )
    end
  end

  def finish(conn, _params) do
    user = conn.assigns.pending_user

    if TwoStep.enabled?(user),
      do: Auth.log_in_staff(conn, user),
      else: redirect(conn, to: ~p"/two-step/setup")
  end

  def delete(conn, _params), do: Auth.log_out_staff(conn)

  # TODO(production): turn on with REQUIRE_STAFF_TWO_STEP=true
  defp two_step_required?, do: Application.get_env(:keepsakes, :require_staff_two_step, false)

  defp put_page_title(conn, _opts), do: assign(conn, :page_title, "Sign in")

  defp require_pending(conn, _opts) do
    case Auth.pending_user(conn) do
      nil -> conn |> redirect(to: ~p"/log-in") |> halt()
      user -> assign(conn, :pending_user, user)
    end
  end
end
