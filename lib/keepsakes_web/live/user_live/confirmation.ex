defmodule KeepsakesWeb.UserLive.Confirmation do
  @moduledoc """
  Landing page for every emailed link (confirm email, sign in, reset
  password). The token is only spent when the user presses the button, so
  link previewers and mail scanners can't use it up.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} shell={:auth}>
      <div class="flex flex-col gap-2">
        <h1 class="text-4xl font-bold leading-[1.1] sm:text-[40px]">{@heading}</h1>
        <p class="text-[17px] text-ks-muted">{@user.email}</p>
      </div>

      <.form
        for={@form}
        id={@form_id}
        class="flex max-w-[440px] flex-col gap-2.5"
        phx-mounted={JS.focus_first()}
        phx-submit="submit"
        action={@action}
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <%= if @current_scope do %>
          <.button variant="primary" size="lg" class="w-full" phx-disable-with="One moment…">
            {@button_label}
          </.button>
        <% else %>
          <.button
            name={@form[:remember_me].name}
            value="true"
            variant="primary"
            size="lg"
            class="w-full"
            phx-disable-with="One moment…"
          >
            {@button_label} and stay logged in
          </.button>
          <.button size="lg" class="w-full" phx-disable-with="One moment…">
            {@button_label} only this time
          </.button>
        <% end %>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       socket
       |> assign(user: user, form: form, trigger_submit: false, page_title: "Continue")
       |> assign_mode(user, params)}
    else
      {:ok,
       socket
       |> put_flash(:error, "That link is invalid or it has expired.")
       |> push_navigate(to: ~p"/auth/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end

  defp assign_mode(socket, %{confirmed_at: nil}, _params) do
    assign(socket,
      heading: "Confirm your email",
      button_label: "Confirm",
      form_id: "confirmation_form",
      action: ~p"/auth/log-in?_action=confirmed"
    )
  end

  defp assign_mode(socket, _user, %{"reset" => _}) do
    assign(socket,
      heading: "Reset your password",
      button_label: "Continue",
      form_id: "reset_form",
      action: ~p"/auth/log-in?_action=reset"
    )
  end

  defp assign_mode(socket, _user, _params) do
    assign(socket,
      heading: "Sign in to Keepsake",
      button_label: "Log in",
      form_id: "login_form",
      action: ~p"/auth/log-in"
    )
  end
end
