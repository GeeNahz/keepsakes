defmodule KeepsakesWeb.SettingsLive.Sharing do
  @moduledoc """
  `/app/settings/sharing`: what every new share link starts with. Each
  album's Share page can still change its own link afterwards.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  alias Keepsakes.{Accounts, Entitlements}
  alias Keepsakes.Sharing.ShareLink

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:sharing}
      title="Sharing defaults"
      subtitle="New share links start with these settings. You can still change any album's link on its Share page."
    >
      <.settings_card id="sharing-defaults" title="New share links">
        <.form
          for={@form}
          id="sharing-form"
          phx-change="save"
          class="flex flex-col gap-4 [&_.fieldset]:mb-0"
        >
          <.input
            field={@form[:share_code_mode]}
            type="select"
            label="Access code"
            options={[{"Generate one automatically", "auto"}, {"Ask me to choose my own", "manual"}]}
          />
          <.input
            field={@form[:share_expires_in]}
            type="select"
            label="Link expires"
            options={[{"Never", "never"}, {"After 7 days", "7"}, {"After 30 days", "30"}]}
          />
          <.input
            field={@form[:share_default_view]}
            type="select"
            label="Guests first see the album as"
            options={ShareLink.view_options()}
          />
          <.input
            field={@form[:share_show_details]}
            type="checkbox"
            label="Show captions and locations"
          />
          <div class="flex flex-col gap-1">
            <.input
              field={@form[:share_allow_downloads]}
              type="checkbox"
              label="Let guests download photos"
              disabled={not @downloads?}
            />
            <.link
              :if={not @downloads?}
              navigate={~p"/app/settings/billing"}
              class="text-[13px] text-ks-muted no-underline hover:text-primary"
            >
              Guest downloads come with Plus and Pro.
              <span class="font-bold text-primary">See plans</span>
            </.link>
          </div>
        </.form>
      </.settings_card>
    </.settings_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: "Sharing defaults",
       downloads?: Entitlements.can?(scope, :guest_downloads),
       form: to_form(Accounts.change_sharing_defaults(scope.user))
     )}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_sharing_defaults(scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_scope: %{scope | user: user},
           form: to_form(Accounts.change_sharing_defaults(user))
         )
         |> put_flash(:info, "Saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
