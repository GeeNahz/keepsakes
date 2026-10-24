defmodule KeepsakesWeb.UserLive.ResetPassword do
  @moduledoc """
  "Forgot password?": emails a one-time link that signs the user in and
  takes them to choose a new password (see `UserSessionController`).
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts
  alias KeepsakesWeb.AuthThrottle

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} shell={:auth}>
      <div class="flex flex-col gap-2">
        <h1 class="text-4xl font-bold leading-[1.1] sm:text-[40px]">Forgot your password?</h1>
        <p class="text-[17px] text-ks-muted">
          Enter your email and we'll send you a link to choose a new one.
        </p>
      </div>

      <%= if @sent do %>
        <div
          id="reset-sent"
          class="flex max-w-[440px] flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-6"
        >
          <p class="flex items-center gap-2 font-bold">
            <.icon name="hero-envelope-open" class="size-5 text-primary" /> Check your inbox
          </p>
          <p class="text-ks-muted">
            If an account exists for that email, a reset link is on its way. It works for 15 minutes.
          </p>
        </div>
      <% else %>
        <.form
          for={@form}
          id="reset_password_form"
          class="flex max-w-[440px] flex-col gap-1"
          phx-submit="send"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            placeholder="you@example.com"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button
            id="reset-submit"
            variant="primary"
            size="lg"
            class="w-full"
            phx-disable-with="Sending…"
          >
            Send reset link
          </.button>
        </.form>
      <% end %>

      <p class="text-[15px] text-ks-muted">
        Remembered it? <.link navigate={~p"/users/log-in"} class="font-bold">Back to log in</.link>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Reset password",
       form: to_form(%{"email" => ""}, as: "user"),
       sent: false,
       client_ip: AuthThrottle.client_ip(get_connect_info(socket, :peer_data))
     )}
  end

  @impl true
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    case AuthThrottle.email_link(socket.assigns.client_ip, email) do
      :ok ->
        # Same response whether or not the email exists (no account enumeration)
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_password_reset_instructions(
            user,
            &url(~p"/users/log-in/#{&1}?reset=1")
          )
        end

        {:noreply, assign(socket, sent: true)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, AuthThrottle.message(reason))}
    end
  end
end
