defmodule KeepsakesWeb.Admin.Auth do
  @moduledoc """
  Admin portal sessions, on the admin host only.

  Staff sign in with their account's email and password, then an
  authenticator code if their account has two-step login on (required for
  everyone with `:require_staff_two_step`, see
  `KeepsakesWeb.Admin.SessionController`). The session (`:staff_token`, its own 12-hour
  token) is separate from the main site's, and the browser keeps it apart
  anyway because cookies are host-only.

  Plugs: `fetch_staff/2` (assigns `@staff_scope`, nil when signed out or no
  longer staff). `on_mount`: `:require_staff`, and `{:permission, key}` on
  each page (403 without it).
  """
  use KeepsakesWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Keepsakes.{Accounts, Audit, Staff}
  alias Keepsakes.Staff.Scope, as: StaffScope

  @pending_key :staff_pending
  # Seconds to finish the code step after the password
  @pending_ttl 600

  ## Plugs

  def fetch_staff(conn, _opts) do
    scope =
      with token when is_binary(token) <- get_session(conn, :staff_token),
           %Accounts.User{} = user <- Accounts.get_user_by_staff_session_token(token) do
        Staff.scope_for(user, ip(conn))
      else
        _ -> nil
      end

    assign(conn, :staff_scope, scope)
  end

  def require_staff(conn, _opts) do
    if conn.assigns[:staff_scope] do
      conn
    else
      conn |> redirect(to: ~p"/log-in") |> halt()
    end
  end

  def redirect_if_staff(conn, _opts) do
    if conn.assigns[:staff_scope], do: conn |> redirect(to: ~p"/") |> halt(), else: conn
  end

  ## The login steps

  @doc "After a correct password: remember who's signing in until the code step."
  def park(conn, user) do
    put_session(conn, @pending_key, %{"user_id" => user.id, "at" => System.system_time(:second)})
  end

  @doc "The staff member between password and code, or nil."
  def pending_user(conn) do
    with %{"user_id" => id, "at" => at} <- get_session(conn, @pending_key),
         true <- System.system_time(:second) - at < @pending_ttl,
         %Accounts.User{} = user <- Accounts.get_user(id),
         true <- Staff.staff?(user) do
      user
    else
      _ -> nil
    end
  end

  @doc "Starts the admin session after the code checked out."
  def log_in_staff(conn, user) do
    token =
      Accounts.generate_staff_session_token(user, %{user_agent: user_agent(conn), ip: ip(conn)})

    Audit.record(
      Staff.scope_for(user, ip(conn)),
      "staff.signed_in",
      {"user", user.id, user.email}
    )

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:staff_token, token)
    |> put_session(:live_socket_id, "staff_sessions:#{Base.url_encode64(token)}")
    |> redirect(to: ~p"/")
  end

  def log_out_staff(conn) do
    if token = get_session(conn, :staff_token), do: Accounts.delete_staff_session_token(token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      KeepsakesWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/log-in")
  end

  ## LiveView

  def on_mount(:require_staff, _params, session, socket) do
    scope =
      with token when is_binary(token) <- session["staff_token"],
           %Accounts.User{} = user <- Accounts.get_user_by_staff_session_token(token) do
        Staff.scope_for(user, peer_ip(socket))
      else
        _ -> nil
      end

    if scope do
      {:cont, Phoenix.Component.assign(socket, :staff_scope, scope)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/log-in")}
    end
  end

  # Pages declare what they need; without it the page is a 403
  def on_mount({:permission, permission}, _params, _session, socket) do
    if StaffScope.can?(socket.assigns.staff_scope, permission),
      do: {:cont, socket},
      else: raise(Staff.Forbidden)
  end

  defp peer_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
  defp user_agent(conn), do: conn |> get_req_header("user-agent") |> List.first()
end
