defmodule KeepsakesWeb.UserLive.Login do
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts
  alias KeepsakesWeb.AuthThrottle

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} shell={:auth}>
      <div class="flex flex-col gap-2">
        <h1 class="text-4xl font-bold leading-[1.1] sm:text-[40px]">
          {if @current_scope, do: "Confirm it's you", else: "Welcome back"}
        </h1>
        <p class="text-[17px] text-ks-muted">
          <%= if @current_scope do %>
            Log in again to change sensitive account settings.
          <% else %>
            Log in to your albums.
          <% end %>
        </p>
      </div>

      <div :if={local_mail_adapter?()} class="alert alert-info max-w-[440px]">
        <.icon name="hero-information-circle" class="size-6 shrink-0" />
        <p>
          Dev mode: emails go to <.link href="/dev/mailbox" class="underline">the local mailbox</.link>.
        </p>
      </div>

      <div class="flex max-w-[440px] flex-col gap-5">
        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          class="flex flex-col gap-1"
          action={~p"/users/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            placeholder="you@example.com"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
          />
          <div class="flex items-center justify-between gap-3">
            <.input
              field={@form[:remember_me]}
              type="checkbox"
              label="Keep me logged in"
              value={true}
            />
            <.link
              id="forgot-password-link"
              navigate={~p"/users/reset-password"}
              class="mb-2 text-sm font-bold"
            >
              Forgot password?
            </.link>
          </div>
          <.button
            id="login-submit"
            variant="primary"
            size="lg"
            class="w-full"
            phx-disable-with="Logging in…"
          >
            Log in
          </.button>

          <div class="divider my-3 text-sm text-ks-muted">or</div>

          <%!-- Same form, so it uses the email typed above; formnovalidate skips the password --%>
          <.button
            id="magic-link-submit"
            name={f[:magic].name}
            value="true"
            variant="outline"
            size="lg"
            class="w-full"
            formnovalidate
          >
            <.icon name="hero-envelope" class="size-5" /> Email me a sign-in link
          </.button>
        </.form>

        <p :if={!@current_scope} class="text-[15px] text-ks-muted">
          New to Keepsake?
          <.link navigate={~p"/users/register"} class="font-bold">Create an account</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       page_title: "Log in",
       form: form,
       trigger_submit: false,
       client_ip: AuthThrottle.client_ip(get_connect_info(socket, :peer_data))
     )}
  end

  @impl true
  def handle_event("submit", %{"user" => %{"magic" => "true", "email" => email}}, socket) do
    case AuthThrottle.email_link(socket.assigns.client_ip, email) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
        end

        info =
          "If your email is in our system, you will receive a sign-in link shortly."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, AuthThrottle.message(reason))}
    end
  end

  # Password log in: let the form POST to the session controller
  def handle_event("submit", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  defp local_mail_adapter? do
    Application.get_env(:keepsakes, Keepsakes.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
