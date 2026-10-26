defmodule KeepsakesWeb.SettingsLive.Security do
  @moduledoc """
  `/app/settings/security`: optional two-step login with an authenticator
  app, and the devices signed in to the account. Needs a recent login.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.SettingsComponents

  on_mount {KeepsakesWeb.UserAuth, :require_sudo_mode}

  alias Keepsakes.Accounts
  alias Keepsakes.Accounts.TwoStep
  alias KeepsakesWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_shell
      flash={@flash}
      current_scope={@current_scope}
      owner={@owner}
      tab={:security}
      title="Security"
      subtitle="Keep your account and your family's photos safe."
    >
      <.settings_card
        id="two-step"
        title="Two-step login"
        description="After your password (or sign-in link), also enter a code from an authenticator app such as Google Authenticator, Microsoft Authenticator or 1Password."
      >
        <%= cond do %>
          <% @recovery_codes -> %>
            <div id="recovery-codes" class="flex flex-col gap-3">
              <p class="rounded-field bg-ks-amber-soft p-3 text-sm text-ks-amber-deep">
                Save these recovery codes somewhere safe. Each works once if you lose your phone. They won't be shown again.
              </p>
              <pre
                id="recovery-code-list"
                class="grid grid-cols-2 gap-2 rounded-field bg-base-200 p-4 font-mono text-[15px]"
              ><span :for={code <- @recovery_codes}>{code}</span></pre>
              <div class="flex flex-wrap gap-2">
                <.button
                  id="copy-recovery-codes"
                  type="button"
                  phx-click={JS.dispatch("ks:copy", detail: %{from: "#recovery-code-list"})}
                >
                  <span data-copy-label>Copy codes</span>
                </.button>
                <.button id="recovery-codes-done" variant="primary" phx-click="codes_saved">
                  I've saved them
                </.button>
              </div>
            </div>
          <% @setup -> %>
            <div id="two-step-setup" class="flex flex-col gap-4 sm:flex-row sm:items-start">
              <div
                id="two-step-qr"
                class="w-fit shrink-0 rounded-field bg-white p-3"
                aria-label="QR code for your authenticator app"
              >
                {Phoenix.HTML.raw(@setup.qr)}
              </div>
              <div class="flex flex-col gap-3">
                <ol class="list-decimal pl-5 text-sm leading-relaxed text-ks-muted">
                  <li>Scan the QR code with your authenticator app.</li>
                  <li>
                    Can't scan? Enter this key instead:
                    <span id="two-step-key" class="font-mono text-base-content">{@setup.key}</span>
                  </li>
                  <li>Type the 6-digit code the app shows.</li>
                </ol>
                <form id="two-step-enable-form" phx-submit="enable" class="flex flex-wrap gap-2">
                  <.code_input id="two-step-enable-code" />
                  <.button variant="primary">Turn on</.button>
                  <.button type="button" phx-click="cancel_setup">Cancel</.button>
                </form>
                <p :if={@code_error} class="text-sm text-error">{@code_error}</p>
              </div>
            </div>
          <% TwoStep.enabled?(@current_scope.user) -> %>
            <div id="two-step-on" class="flex flex-col gap-3">
              <p class="flex items-center gap-2 text-[15px]">
                <.icon name="hero-check-badge" class="size-5 text-primary" />
                On since {date(@current_scope.user.totp_enabled_at)} · {length(
                  @current_scope.user.recovery_codes
                )} recovery codes left
              </p>
              <form id="two-step-manage-form" phx-submit="manage" class="flex flex-wrap gap-2">
                <.code_input id="two-step-manage-code" placeholder="Code or recovery code" />
                <.button name="do" value="regenerate">New recovery codes</.button>
                <.button name="do" value="disable" variant="danger">Turn off</.button>
              </form>
              <p class="text-[13px] text-ks-muted">
                Enter a current code from your app to make either change.
              </p>
              <p :if={@code_error} class="text-sm text-error">{@code_error}</p>
            </div>
          <% true -> %>
            <div class="flex flex-wrap items-center justify-between gap-3">
              <span class="text-[15px] text-ks-muted">Off</span>
              <.button id="two-step-start" variant="primary" phx-click="start_setup">
                Set up two-step login
              </.button>
            </div>
        <% end %>
      </.settings_card>

      <.settings_card
        id="devices"
        title="Signed-in devices"
        description="Sign out anywhere you don't recognise. Sessions last 14 days unless you choose Keep me logged in."
      >
        <ul class="flex flex-col divide-y divide-base-300">
          <li
            :for={session <- @sessions}
            id={"session-#{session.id}"}
            class="flex flex-wrap items-center justify-between gap-3 py-3"
          >
            <div class="flex items-center gap-3">
              <.icon name={device_icon(session.user_agent)} class="size-6 shrink-0 text-ks-muted" />
              <div class="flex flex-col">
                <span class="font-medium">
                  {device_name(session.user_agent)}
                  <.badge :if={session.token == @current_token} variant="ready" class="ml-1">
                    This device
                  </.badge>
                </span>
                <span class="text-sm text-ks-muted">
                  {session.ip || "Unknown location"} · signed in {date(session.inserted_at)}
                </span>
              </div>
            </div>
            <.button
              :if={session.token != @current_token}
              id={"sign-out-#{session.id}"}
              size="sm"
              phx-click="sign_out"
              phx-value-id={session.id}
            >
              Sign out
            </.button>
          </li>
        </ul>
        <.button
          :if={length(@sessions) > 1}
          id="sign-out-others"
          class="self-start"
          phx-click="sign_out_others"
        >
          Sign out all other devices
        </.button>
      </.settings_card>
    </.settings_shell>
    """
  end

  attr :id, :string, required: true
  attr :placeholder, :string, default: "123 456"

  defp code_input(assigns) do
    ~H"""
    <input
      id={@id}
      name="code"
      type="text"
      inputmode="text"
      autocomplete="one-time-code"
      placeholder={@placeholder}
      required
      class="input h-11 w-48 border-ks-field bg-base-100 font-mono tracking-wider"
    />
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Security",
       current_token: session["user_token"],
       setup: nil,
       recovery_codes: nil,
       code_error: nil
     )
     |> load_sessions()}
  end

  defp load_sessions(socket),
    do: assign(socket, sessions: Accounts.list_sessions(socket.assigns.current_scope.user))

  @impl true
  def handle_event("start_setup", _params, socket) do
    user = socket.assigns.current_scope.user
    secret = TwoStep.new_secret()

    {:noreply,
     assign(socket,
       code_error: nil,
       setup: %{secret: secret, qr: TwoStep.qr_svg(user, secret), key: TwoStep.manual_key(secret)}
     )}
  end

  def handle_event("cancel_setup", _params, socket),
    do: {:noreply, assign(socket, setup: nil, code_error: nil)}

  def handle_event("enable", %{"code" => code}, %{assigns: %{setup: %{secret: secret}}} = socket) do
    case TwoStep.enable(socket.assigns.current_scope.user, secret, code) do
      {:ok, user, codes} ->
        {:noreply,
         socket
         |> put_user(user)
         |> assign(setup: nil, recovery_codes: codes, code_error: nil)
         |> put_flash(:info, "Two-step login is on.")}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, code_error: "That code didn't match. Try the newest one.")}
    end
  end

  def handle_event("codes_saved", _params, socket),
    do: {:noreply, assign(socket, recovery_codes: nil)}

  def handle_event("manage", %{"code" => code, "do" => "regenerate"}, socket) do
    case TwoStep.regenerate_recovery_codes(socket.assigns.current_scope.user, code) do
      {:ok, user, codes} ->
        {:noreply, socket |> put_user(user) |> assign(recovery_codes: codes, code_error: nil)}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, code_error: "That code didn't work.")}
    end
  end

  def handle_event("manage", %{"code" => code, "do" => "disable"}, socket) do
    case TwoStep.disable(socket.assigns.current_scope.user, code) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_user(user)
         |> assign(code_error: nil)
         |> put_flash(:info, "Two-step login is off.")}

      {:error, :invalid_code} ->
        {:noreply, assign(socket, code_error: "That code didn't work.")}
    end
  end

  def handle_event("sign_out", %{"id" => id}, socket) do
    case Accounts.delete_session(socket.assigns.current_scope.user, id) do
      {:ok, token} ->
        UserAuth.disconnect_sessions([token])
        {:noreply, socket |> load_sessions() |> put_flash(:info, "Signed out that device.")}

      _ ->
        {:noreply, load_sessions(socket)}
    end
  end

  def handle_event("sign_out_others", _params, socket) do
    tokens =
      Accounts.delete_other_sessions(
        socket.assigns.current_scope.user,
        socket.assigns.current_token
      )

    UserAuth.disconnect_sessions(tokens)
    {:noreply, socket |> load_sessions() |> put_flash(:info, "Signed out everywhere else.")}
  end

  defp put_user(socket, user),
    do: assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})

  defp date(at), do: Calendar.strftime(at, "%-d %B %Y")

  @doc false
  # "Chrome on Windows", from a user-agent string (rough, for display only)
  def device_name(nil), do: "Unknown device"

  def device_name(agent) do
    browser =
      cond do
        agent =~ "Edg/" -> "Edge"
        agent =~ "OPR/" -> "Opera"
        agent =~ "Firefox/" -> "Firefox"
        agent =~ "Chrome/" -> "Chrome"
        agent =~ "Safari/" -> "Safari"
        true -> "Browser"
      end

    os =
      cond do
        agent =~ "iPhone" -> "iPhone"
        agent =~ "iPad" -> "iPad"
        agent =~ "Android" -> "Android"
        agent =~ "Windows" -> "Windows"
        agent =~ "Mac OS X" -> "Mac"
        agent =~ "Linux" -> "Linux"
        true -> nil
      end

    if os, do: "#{browser} on #{os}", else: browser
  end

  defp device_icon(agent) when is_binary(agent) do
    if agent =~ ~r/iPhone|Android|Mobile/,
      do: "hero-device-phone-mobile",
      else: "hero-computer-desktop"
  end

  defp device_icon(_agent), do: "hero-computer-desktop"
end
