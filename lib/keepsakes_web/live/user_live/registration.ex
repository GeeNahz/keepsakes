defmodule KeepsakesWeb.UserLive.Registration do
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Accounts, Settings}
  alias Keepsakes.Accounts.User
  alias KeepsakesWeb.AuthThrottle

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} shell={:auth}>
      <div class="flex flex-col gap-2">
        <h1 class="text-4xl font-bold leading-[1.1] sm:text-[40px]">Create your account</h1>
        <p class="text-[17px] text-ks-muted">
          Start an album, add your photos, and share it with the people who were there.
        </p>
      </div>

      <%= if @signups_open do %>
        <.form
          for={@form}
          id="registration_form"
          class="flex max-w-[440px] flex-col gap-1"
          action={~p"/users/log-in?_action=registered"}
          method="post"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
        >
          <div class="grid gap-x-3 sm:grid-cols-2">
            <.input
              field={@form[:first_name]}
              label="First name"
              autocomplete="given-name"
              placeholder="Godswill"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:last_name]}
              label="Last name"
              autocomplete="family-name"
              placeholder="Nasara"
            />
          </div>
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            placeholder="you@example.com"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            placeholder="At least 12 characters"
            required
          />
          <.button
            id="registration-submit"
            variant="primary"
            size="lg"
            class="mt-1.5 w-full"
            phx-disable-with="Creating account…"
          >
            Create account
          </.button>
          <p class="mt-3 text-[15px] text-ks-muted">
            Already have an account?
            <.link navigate={~p"/users/log-in"} class="font-bold">Log in</.link>
          </p>
        </.form>
      <% else %>
        <div
          id="signups-closed"
          class="flex max-w-[440px] flex-col gap-3 rounded-box border border-base-300 bg-base-100 p-6"
        >
          <p class="font-bold">New sign-ups are paused for now.</p>
          <p class="text-ks-muted">
            We're making some improvements. Please check back soon.
          </p>
          <p class="text-[15px] text-ks-muted">
            Already have an account?
            <.link navigate={~p"/users/log-in"} class="font-bold">Log in</.link>
          </p>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: KeepsakesWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Create account",
        signups_open: Settings.get(:signups_open),
        client_ip: AuthThrottle.client_ip(get_connect_info(socket, :peer_data)),
        trigger_submit: false
      )
      |> assign_form(Accounts.change_user_registration(%User{}))

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    with true <- Settings.get(:signups_open) || {:error, :closed},
         :ok <- AuthThrottle.register(socket.assigns.client_ip),
         {:ok, user} <- Accounts.register_user(user_params) do
      {:ok, _} = Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

      # Submit the same email + password to the session controller, which
      # logs the new user in (LiveViews can't write the session cookie).
      {:noreply, assign(socket, trigger_submit: true, form: to_form(user_params, as: "user"))}
    else
      {:error, :closed} ->
        {:noreply, assign(socket, signups_open: false)}

      {:error, {:rate_limited, _} = reason} ->
        {:noreply, put_flash(socket, :error, AuthThrottle.message(reason))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
