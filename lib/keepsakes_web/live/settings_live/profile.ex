defmodule KeepsakesWeb.SettingsLive.Profile do
  @moduledoc "`/app/settings/profile`: name, a short bio and the profile photo."
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  alias Keepsakes.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:profile}
      title="Profile"
      subtitle="How you appear on Keepsake and to the people you share albums with."
    >
      <.settings_card id="avatar" title="Profile photo">
        <form
          id="avatar-form"
          phx-change="validate_avatar"
          phx-submit="save_avatar"
          class="flex flex-wrap items-center gap-5"
        >
          <.avatar
            id="avatar-preview"
            name={Accounts.User.full_name(@current_scope.user)}
            src={Accounts.avatar_url(@current_scope.user)}
            class="size-20 text-2xl"
          />
          <div class="flex flex-col gap-2">
            <div class="flex flex-wrap gap-2">
              <label
                for={@uploads.avatar.ref}
                class="btn btn-outline min-h-11 cursor-pointer rounded-field border-ks-field bg-base-100 px-4 font-bold"
              >
                {if @current_scope.user.avatar_key, do: "Change photo", else: "Upload a photo"}
              </label>
              <.live_file_input upload={@uploads.avatar} class="sr-only" />
              <.button
                :if={@current_scope.user.avatar_key}
                id="remove-avatar"
                type="button"
                phx-click="remove_avatar"
              >
                Remove
              </.button>
            </div>
            <span class="text-[13px] text-ks-muted">
              JPG, PNG, HEIC or WebP, up to 5 MB. It's cropped to a square.
            </span>
            <p :for={err <- upload_errors(@uploads.avatar)} class="text-sm text-error">
              {error_text(err)}
            </p>
            <p
              :for={entry <- @uploads.avatar.entries}
              :if={upload_errors(@uploads.avatar, entry) != []}
              class="text-sm text-error"
            >
              {Enum.map_join(upload_errors(@uploads.avatar, entry), " ", &error_text/1)}
            </p>
          </div>
        </form>
      </.settings_card>

      <.settings_card id="profile" title="About you">
        <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save">
          <div class="grid gap-x-3 sm:grid-cols-2">
            <.input field={@form[:first_name]} label="First name" autocomplete="given-name" required />
            <.input field={@form[:last_name]} label="Last name" autocomplete="family-name" />
          </div>
          <.input
            field={@form[:bio]}
            type="textarea"
            label="Short bio"
            rows="2"
            maxlength="160"
            placeholder="Optional · e.g. Mum of two, collecting our family's moments"
          />
          <.button variant="primary" phx-disable-with="Saving…">Save profile</.button>
        </.form>
      </.settings_card>
    </.settings_shell>
    """
  end

  defp error_text(:too_large), do: "That photo is over 5 MB."
  defp error_text(:not_accepted), do: "Use a JPG, PNG, HEIC or WebP photo."
  defp error_text(:too_many_files), do: "Choose one photo."
  defp error_text(_), do: "That photo couldn't be used."

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(page_title: "Profile", form: to_form(Accounts.change_profile(user)))
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .heic .heif .webp),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_profile(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_user(user)
         |> assign(form: to_form(Accounts.change_profile(user)))
         |> put_flash(:info, "Profile saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :update))}
    end
  end

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}
  def handle_event("save_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("remove_avatar", _params, socket) do
    {:ok, user} = Accounts.remove_avatar(socket.assigns.current_scope.user)
    {:noreply, socket |> put_user(user) |> put_flash(:info, "Photo removed.")}
  end

  # The photo is saved as soon as it finishes uploading
  defp handle_progress(:avatar, %{done?: true} = entry, socket) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Accounts.set_avatar(socket.assigns.current_scope.user, path)}
      end)

    case result do
      {:ok, user} ->
        {:noreply, socket |> put_user(user) |> put_flash(:info, "Photo updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That photo couldn't be read. Try another.")}
    end
  end

  defp handle_progress(:avatar, _entry, socket), do: {:noreply, socket}

  defp put_user(socket, user),
    do: assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})
end
