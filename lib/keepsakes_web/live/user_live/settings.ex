defmodule KeepsakesWeb.UserLive.Settings do
  use KeepsakesWeb, :live_view

  on_mount {KeepsakesWeb.UserAuth, :require_sudo_mode}

  alias Keepsakes.{Accounts, Templates}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-2xl flex-col gap-6">
        <.header>
          Account settings
          <:subtitle>Your name, sign-in email, password and template for new albums.</:subtitle>
        </.header>

        <section id="name" class="rounded-box border border-base-300 bg-base-100 p-6">
          <h2 class="mb-4 text-lg font-bold">Name</h2>
          <.form for={@name_form} id="name_form" phx-submit="update_name" phx-change="validate_name">
            <div class="grid gap-x-3 sm:grid-cols-2">
              <.input
                field={@name_form[:first_name]}
                label="First name"
                autocomplete="given-name"
                required
              />
              <.input field={@name_form[:last_name]} label="Last name" autocomplete="family-name" />
            </div>
            <.button variant="primary" phx-disable-with="Saving…">Save name</.button>
          </.form>
        </section>

        <section id="email" class="rounded-box border border-base-300 bg-base-100 p-6">
          <h2 class="mb-4 text-lg font-bold">Email</h2>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
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
        </section>

        <section id="password" class="rounded-box border border-base-300 bg-base-100 p-6">
          <h2 class="mb-1 text-lg font-bold">
            {if @has_password, do: "Password", else: "Set a password"}
          </h2>
          <p :if={!@has_password} class="mb-4 text-sm text-ks-muted">
            Your account has no password yet. Choose one to log in with your email and password.
          </p>
          <.form
            for={@password_form}
            id="password_form"
            class="mt-4"
            action={~p"/users/update-password"}
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
            <.button variant="primary" phx-disable-with="Saving…">
              Save password
            </.button>
          </.form>
        </section>

        <section id="default-template" class="rounded-box border border-base-300 bg-base-100 p-6">
          <h2 class="mb-1 text-lg font-bold">Template for new albums</h2>
          <p class="mb-4 text-sm text-ks-muted">
            New albums start with this look for guests. You can change any album's template from its page.
          </p>
          <.form for={@template_form} id="default_template_form" phx-change="set_default_template">
            <.input
              field={@template_form[:slug]}
              type="select"
              label="Template"
              options={
                Enum.map(@templates, fn template ->
                  label = if template.premium, do: "#{template.name} (Premium)", else: template.name
                  [key: label, value: template.slug, disabled: template.premium and not @premium?]
                end)
              }
            />
          </.form>
        </section>
      </div>
    </Layouts.app>
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

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:current_email, user.email)
      |> assign(:has_password, not is_nil(user.hashed_password))
      |> assign(:name_form, to_form(Accounts.change_user_name(user)))
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:templates, Templates.list_templates(socket.assigns.current_scope))
      |> assign(:premium?, Templates.premium?(socket.assigns.current_scope))
      |> assign_template_form(Templates.default_for(socket.assigns.current_scope))

    {:ok, socket}
  end

  defp assign_template_form(socket, template),
    do: assign(socket, :template_form, to_form(%{"slug" => template.slug}, as: :default_template))

  @impl true
  def handle_event("validate_name", %{"user" => user_params}, socket) do
    name_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_name(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, name_form: name_form)}
  end

  def handle_event("update_name", %{"user" => user_params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_user_name(scope.user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, %{scope | user: user})
         |> assign(:name_form, to_form(Accounts.change_user_name(user)))
         |> put_flash(:info, "Name updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, name_form: to_form(changeset, action: :update))}
    end
  end

  def handle_event("set_default_template", %{"default_template" => %{"slug" => slug}}, socket) do
    scope = socket.assigns.current_scope

    with %{} = template <- Templates.get_template(scope, slug),
         {:ok, user} <- Templates.set_default_template(scope, template) do
      {:noreply,
       socket
       |> assign(:current_scope, %{scope | user: user})
       |> assign_template_form(template)
       |> put_flash(:info, "New albums will use #{template.name}.")}
    else
      {:error, :premium} ->
        {:noreply, put_flash(socket, :error, "Premium templates need the Plus or Pro plan.")}

      _ ->
        {:noreply, put_flash(socket, :error, "That template isn't available.")}
    end
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
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
