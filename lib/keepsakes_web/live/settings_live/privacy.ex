defmodule KeepsakesWeb.SettingsLive.Privacy do
  @moduledoc """
  `/app/settings/privacy`: download everything, or delete the account (a
  #{Keepsakes.Accounts.deletion_grace_days()}-day pause first, so it can be
  restored). Needs a recent login.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  on_mount {KeepsakesWeb.UserAuth, :require_sudo_mode}

  alias Keepsakes.{Accounts, Exports, Format}
  alias KeepsakesWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:privacy}
      title="Data & privacy"
      subtitle="Take a copy of everything, or close your account."
    >
      <.settings_card
        id="export"
        title="Export everything"
        description="A zip with every album: each photo at full display size (2400 px) and a file with its titles, dates, captions, places and people. We'll email you when it's ready."
      >
        <%= case @export do %>
          <% %{status: "pending"} -> %>
            <p id="export-status" class="flex items-center gap-2 text-[15px] text-ks-muted">
              <span class="loading loading-spinner loading-sm text-primary"></span>
              Preparing your export. We'll email you a link.
            </p>
          <% %{status: "ready"} = export -> %>
            <div id="export-status" class="flex flex-wrap items-center justify-between gap-3">
              <span class="text-[15px]">
                Ready · {Format.bytes(export.bytes)} · until {date(export.expires_at)}
              </span>
              <div class="flex gap-2">
                <.button
                  id="download-export"
                  variant="primary"
                  href={~p"/app/settings/privacy/exports/#{export.id}"}
                >
                  Download
                </.button>
                <.button id="new-export" phx-click="export">Make a new one</.button>
              </div>
            </div>
          <% export -> %>
            <div class="flex flex-wrap items-center justify-between gap-3">
              <span :if={export && export.status == "failed"} class="text-sm text-error">
                The last export didn't finish. Please try again.
              </span>
              <.button id="start-export" variant="primary" phx-click="export">
                Export everything
              </.button>
            </div>
        <% end %>
      </.settings_card>

      <.settings_card
        id="delete-account"
        title="Delete account"
        description={"Your account is paused straight away: you're signed out, shared links stop opening and your plan won't renew. Everything is deleted for good after #{Accounts.deletion_grace_days()} days; log in before then to restore it."}
        class="border-error/40"
      >
        <form id="delete-account-form" phx-submit="delete" class="flex flex-col gap-3">
          <label for="confirm-email" class="text-sm">
            Type your email, <span class="font-bold">{@current_scope.user.email}</span>, to confirm.
          </label>
          <div class="flex flex-wrap gap-2">
            <input
              id="confirm-email"
              name="email"
              type="email"
              autocomplete="off"
              required
              class="input h-11 min-w-0 flex-1 border-ks-field bg-base-100"
            />
            <.button variant="danger">Delete my account</.button>
          </div>
          <p :if={@delete_error} id="delete-error" class="text-sm text-error">{@delete_error}</p>
        </form>
      </.settings_card>
    </.settings_shell>
    """
  end

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Exports.subscribe(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Data & privacy",
       export: Exports.latest(socket.assigns.current_scope),
       delete_error: nil
     )}
  end

  @impl true
  def handle_event("export", _params, socket) do
    {:ok, export} = Exports.request(socket.assigns.current_scope)
    {:noreply, assign(socket, export: export)}
  end

  def handle_event("delete", %{"email" => typed}, socket) do
    user = socket.assigns.current_scope.user

    if String.downcase(String.trim(typed)) == String.downcase(user.email) do
      {:ok, _user, tokens} = Accounts.request_deletion(user)
      UserAuth.disconnect_sessions(tokens)

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Your account is paused and will be deleted in #{Accounts.deletion_grace_days()} days. Log in before then to restore it."
       )
       |> redirect(to: ~p"/")}
    else
      {:noreply, assign(socket, delete_error: "That doesn't match your email.")}
    end
  end

  # The export finished (or failed) in the background
  @impl true
  def handle_info({:export_updated, export}, socket),
    do: {:noreply, assign(socket, export: export)}
end
