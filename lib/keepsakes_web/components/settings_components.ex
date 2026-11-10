defmodule KeepsakesWeb.SettingsComponents do
  @moduledoc """
  The settings area: a tab list beside the content on wide screens and a
  scrolling row of tabs on phones, inside the portal shell. Each tab is
  its own LiveView under `/app/settings/...`; this draws what they share.
  """
  use KeepsakesWeb, :html

  @tabs [
    {:profile, "Profile", "hero-user-circle", "/app/settings/profile"},
    {:account, "Account", "hero-envelope", "/app/settings/account"},
    {:security, "Security", "hero-shield-check", "/app/settings/security"},
    {:notifications, "Notifications", "hero-bell", "/app/settings/notifications"},
    {:sharing, "Sharing defaults", "hero-link", "/app/settings/sharing"},
    {:templates, "Templates", "hero-swatch", "/app/settings/templates"},
    {:billing, "Billing", "hero-credit-card", "/app/settings/billing"},
    {:referrals, "Referrals", "hero-gift", "/app/settings/referrals"},
    {:domains, "Domains", "hero-globe-alt", "/app/settings/domains"},
    {:privacy, "Data & privacy", "hero-lock-closed", "/app/settings/privacy"}
  ]

  @doc "Settings tabs as `{id, label, icon, path}`."
  def tabs, do: @tabs

  @doc """
  The settings frame. Pass the shell assigns through, the current `tab`,
  a `title` and optional `subtitle`; the tab's content goes inside.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :owner, :map, required: true
  attr :tab, :atom, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :wide, :boolean, default: false, doc: "let the content use the full width (billing)"
  slot :inner_block, required: true

  def settings_shell(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[1100px] flex-col gap-6 lg:flex-row lg:items-start lg:gap-10">
        <nav
          id="settings-tabs"
          aria-label="Settings"
          class="-mx-4 flex shrink-0 gap-1.5 overflow-x-auto px-4 pb-1 [scrollbar-width:none] lg:sticky lg:top-24 lg:mx-0 lg:w-56 lg:flex-col lg:overflow-visible lg:px-0 [&::-webkit-scrollbar]:hidden"
        >
          <span class="hidden px-3 pb-2 text-[13px] font-bold uppercase tracking-[0.06em] text-ks-muted lg:block">
            Settings
          </span>
          <.link
            :for={{id, label, icon, path} <- @tabs}
            id={"settings-tab-#{id}"}
            navigate={path}
            aria-current={id == @tab && "page"}
            phx-mounted={id == @tab && JS.dispatch("ks:reveal")}
            class={[
              "flex shrink-0 items-center gap-2.5 rounded-field px-3 py-2.5 text-[15px] no-underline transition-colors",
              if(id == @tab,
                do: "bg-ks-teal-soft font-bold text-base-content",
                else: "text-ks-muted hover:bg-base-100 hover:text-base-content"
              )
            ]}
          >
            <.icon name={icon} class="size-[18px] shrink-0" />
            <span class="whitespace-nowrap">{label}</span>
          </.link>
        </nav>

        <div class={["flex min-w-0 flex-1 flex-col gap-6", !@wide && "lg:max-w-[720px]"]}>
          <div class="flex flex-col gap-1.5">
            <h1 class="text-[32px] font-bold">{@title}</h1>
            <p :if={@subtitle} class="text-base text-ks-muted">{@subtitle}</p>
          </div>
          {render_slot(@inner_block)}
        </div>
      </div>
    </Layouts.app>
    """
  end

  @doc "A titled card for one group of settings."
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def settings_card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["flex flex-col gap-4 rounded-2xl border border-base-300 bg-base-100 p-6", @class]}
    >
      <div class="flex flex-col gap-1">
        <h2 class="text-lg font-bold">{@title}</h2>
        <p :if={@description} class="text-sm leading-relaxed text-ks-muted">{@description}</p>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
