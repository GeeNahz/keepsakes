defmodule KeepsakesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KeepsakesWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  # Placeholder until Stage 5 entitlements supply the plan's storage limit
  @placeholder_storage_mb 1024

  @doc """
  Renders the app layout. Every LiveView starts with it.

  ## Shells

    * `:owner` (default) - the owner portal: header with "My albums" and the
      avatar menu, the album sidebar with the storage meter. Falls back to
      `:plain` when nobody is logged in.
    * `:auth` - the split register/log-in screen: form on the left, the
      dark polaroid panel on the right.
    * `:plain` - just the logo bar, for dev pages and simple public pages.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app>

      <Layouts.app flash={@flash} current_scope={@current_scope} shell={:auth}>
        ...register form...
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :shell, :atom, values: [:owner, :auth, :plain], default: :owner

  slot :inner_block, required: true

  def app(%{shell: :owner, current_scope: %{user: %{}}} = assigns) do
    assigns = assign(assigns, :storage_mb, @placeholder_storage_mb)

    ~H"""
    <div class="flex min-h-screen flex-col bg-base-200">
      <header class="flex items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 py-3.5 sm:px-8">
        <.link navigate={~p"/albums"} class="text-base-content no-underline">
          <.logo />
        </.link>
        <nav class="flex items-center gap-5">
          <.link
            navigate={~p"/albums"}
            class="text-[15px] font-medium text-base-content no-underline hover:text-primary"
          >
            My albums
          </.link>
          <.user_menu user={@current_scope.user} />
        </nav>
      </header>

      <div class="grid flex-1 md:grid-cols-[minmax(200px,240px)_minmax(0,1fr)]">
        <aside
          id="album-sidebar"
          class="hidden flex-col gap-1.5 border-r border-base-300 bg-base-100 px-5 py-7 md:flex"
        >
          <div class="px-3 pb-2 text-[13px] font-bold uppercase tracking-[0.06em] text-ks-muted">
            My albums
          </div>
          <p class="rounded-field bg-base-200 p-3 text-sm leading-[1.45] text-ks-muted">
            No albums yet. Your albums will be listed here.
          </p>
          <div class="mt-auto px-3 pt-4">
            <.meter
              id="storage-meter"
              label="Storage"
              value={0}
              max={@storage_mb}
              text={"0 MB of #{format_mb(@storage_mb)}"}
            />
          </div>
        </aside>

        <main class="flex min-w-0 flex-col">
          <.confirm_email_banner user={@current_scope.user} />
          <div class="flex flex-1 flex-col px-4 py-10 sm:px-8">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def app(%{shell: :auth} = assigns) do
    ~H"""
    <div class="grid min-h-screen bg-base-200 lg:grid-cols-2">
      <main class="flex flex-col justify-center gap-8 px-4 py-14 sm:px-[8%]">
        <.link navigate={~p"/"} class="w-fit text-base-content no-underline">
          <.logo size={32} wordmark_class="text-[22px]" />
        </.link>
        {render_slot(@inner_block)}
      </main>

      <aside class="relative hidden flex-col items-center justify-center gap-10 overflow-hidden bg-ks-night px-8 py-14 lg:flex">
        <div class="relative size-[340px]" aria-hidden="true">
          <div class="absolute left-0 top-[30px] w-[220px] -rotate-8 rounded bg-white px-3 pb-9 pt-3 shadow-[0_18px_40px_rgba(0,0,0,0.45)]">
            <div class="flex h-[170px] items-center justify-center bg-ks-tint-sand">
              <.icon name="hero-photo" class="size-10 text-base-content/35" />
            </div>
          </div>
          <div class="absolute right-0 top-0 w-[220px] rotate-5 rounded bg-white px-3 pb-3.5 pt-3 shadow-[0_18px_40px_rgba(0,0,0,0.45)]">
            <div class="flex h-[170px] items-center justify-center bg-ks-tint-sage">
              <.icon name="hero-photo" class="size-10 text-base-content/35" />
            </div>
            <div class="pt-2.5 font-hand text-2xl text-base-content">First birthday</div>
            <div class="font-mono text-xs text-ks-muted">April 2019</div>
          </div>
        </div>
        <div class="flex max-w-[380px] flex-col gap-2.5 text-center">
          <p class="font-display text-[28px] font-bold leading-[1.2] text-white">
            Every memory, in the order it happened.
          </p>
          <p class="text-base text-ks-night-text">
            Albums become a timeline your family can open with a link and a private code.
          </p>
        </div>
      </aside>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-base-200">
      <header class="flex items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 py-3.5 sm:px-8">
        <.link navigate={~p"/"} class="text-base-content no-underline">
          <.logo />
        </.link>
        <div class="flex items-center gap-4">
          <%= if @current_scope && @current_scope.user do %>
            <.user_menu user={@current_scope.user} />
          <% else %>
            <.link navigate={~p"/users/log-in"} class="text-[15px] font-medium">Log in</.link>
          <% end %>
        </div>
      </header>

      <main class="flex-1 px-4 py-10 sm:px-8">
        <div class="mx-auto max-w-5xl">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :user, :map, required: true

  defp user_menu(assigns) do
    ~H"""
    <div id="user-menu" class="dropdown dropdown-end">
      <div
        id="user-menu-button"
        tabindex="0"
        role="button"
        aria-label="Account menu"
        class="cursor-pointer rounded-full transition hover:ring-4 hover:ring-ks-teal-soft focus-visible:ring-4 focus-visible:ring-ks-teal-soft"
      >
        <.avatar name={Keepsakes.Accounts.User.full_name(@user)} />
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-20 mt-3 w-64 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
      >
        <div class="px-3 py-2">
          <p class="truncate font-bold">{Keepsakes.Accounts.User.full_name(@user)}</p>
          <p class="truncate text-sm text-ks-muted">{@user.email}</p>
        </div>
        <ul class="menu w-full p-0">
          <li>
            <.link navigate={~p"/albums"}>
              <.icon name="hero-photo" /> My albums
            </.link>
          </li>
          <li>
            <.link id="user-menu-settings" navigate={~p"/users/settings"}>
              <.icon name="hero-cog-6-tooth" /> Settings
            </.link>
          </li>
          <li>
            <.link id="user-menu-log-out" href={~p"/users/log-out"} method="delete">
              <.icon name="hero-arrow-right-start-on-rectangle" /> Log out
            </.link>
          </li>
        </ul>
        <div class="flex items-center justify-between border-t border-base-300 px-3 pb-1 pt-3">
          <span class="text-sm text-ks-muted">Theme</span>
          <.theme_toggle />
        </div>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true

  defp confirm_email_banner(%{user: %{confirmed_at: nil}} = assigns) do
    ~H"""
    <div
      id="confirm-email-banner"
      class="flex flex-wrap items-center justify-between gap-3 border-b border-ks-amber-soft bg-ks-amber-soft px-4 py-3 text-sm text-ks-amber-deep sm:px-8"
    >
      <p class="flex items-center gap-2">
        <.icon name="hero-envelope" class="size-5 shrink-0" />
        <span>
          Confirm your email. We sent a link to <strong>{@user.email}</strong>.
        </span>
      </p>
      <.form for={%{}} action={~p"/users/confirm/resend"} id="resend-confirmation-form">
        <.button id="resend-confirmation" size="sm" variant="outline">Resend link</.button>
      </.form>
    </div>
    """
  end

  defp confirm_email_banner(assigns), do: ~H""

  defp format_mb(mb) when mb >= 1024 and rem(mb, 1024) == 0, do: "#{div(mb, 1024)} GB"
  defp format_mb(mb), do: "#{mb} MB"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=keepsake]_&]:left-1/3 [[data-theme=keepsake-night]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="keepsake"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="keepsake-night"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
