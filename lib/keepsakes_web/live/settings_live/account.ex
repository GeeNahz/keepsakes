defmodule KeepsakesWeb.SettingsLive.Account do
  @moduledoc """
  `/app/settings/account`: sign-in email (changed through a confirmation
  link sent to the new address) and password. Needs a recent login.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  on_mount {KeepsakesWeb.UserAuth, :require_sudo_mode}

  alias Keepsakes.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:account}
      title="Account"
      subtitle="Your sign-in email and password."
    >
      <.settings_card id="email" title="Email">
        <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with="Changing…">Change email</.button>
        </.form>
      </.settings_card>

      <.settings_card
        id="password"
        title={if @has_password, do: "Password", else: "Set a password"}
        description={
          !@has_password &&
            "Your account has no password yet. Choose one to log in with your email and password."
        }
      >
        <.form
          for={@password_form}
          id="password_form"
          action={~p"/app/settings/account/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            spellcheck="false"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            placeholder="At least 12 characters"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with="Saving…">Save password</.button>
        </.form>
      </.settings_card>
    </.settings_shell>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/app/settings/account")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Account")
     |> assign(:current_email, user.email)
     |> assign(:has_password, not is_nil(user.hashed_password))
     |> assign(
       :email_form,
       to_form(Accounts.change_user_email(user, %{}, validate_unique: false))
     )
     |> assign(
       :password_form,
       to_form(Accounts.change_user_password(user, %{}, hash_password: false))
     )
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/app/settings/account/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
