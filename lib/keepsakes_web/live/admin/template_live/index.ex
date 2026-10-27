defmodule KeepsakesWeb.Admin.TemplateLive.Index do
  @moduledoc """
  `admin.<host>/templates`: the public guest templates, which one new
  albums get, how many albums use each, and whether they're premium or
  hidden. Needs `templates.manage`.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.Templates.{Admin, Theme}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin} staff_scope={@staff_scope} active={:templates}>
      <.header>
        Templates
        <:subtitle>How shared albums look to guests. The default is set in Settings.</:subtitle>
        <:actions>
          <.button id="new-template" variant="primary" navigate={~p"/templates/new"}>
            <.icon name="hero-plus" class="size-4" /> New template
          </.button>
        </:actions>
      </.header>

      <div id="templates" phx-update="stream" class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          :for={{id, {t, count}} <- @streams.templates}
          id={id}
          class="flex flex-col overflow-hidden rounded-box border border-base-300 bg-base-100"
        >
          <div
            style={Theme.css_vars(t.theme)}
            class="flex h-28 items-center justify-center gap-3 bg-ks-guest"
          >
            <div class="w-16 -rotate-6 rounded-sm bg-ks-guest-paper p-1.5 pb-4 shadow">
              <div class="h-10 bg-ks-guest-card"></div>
            </div>
            <span class="font-display text-lg font-bold text-ks-guest-ink">{t.name}</span>
          </div>
          <div class="flex flex-1 flex-col gap-2 p-4">
            <div class="flex flex-wrap items-center gap-1.5">
              <h2 class="font-bold">{t.name}</h2>
              <.badge :if={t.id == @default_id} variant="ready">Default</.badge>
              <.badge :if={t.premium} variant="pending">Premium</.badge>
              <.badge :if={!t.active} variant="muted">Hidden</.badge>
            </div>
            <p :if={t.description} class="text-sm text-ks-muted">{t.description}</p>
            <p class="text-sm text-ks-muted">
              {t.renderer} renderer · {count} {if count == 1, do: "album", else: "albums"}
            </p>
            <.link
              id={"edit-template-#{t.id}"}
              navigate={~p"/templates/#{t.id}"}
              class="mt-auto w-fit text-sm font-bold text-primary"
            >
              Edit template
            </.link>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Templates", default_id: Keepsakes.Templates.system_default().id)
     |> stream_configure(:templates, dom_id: fn {t, _} -> "templates-#{t.id}" end)
     |> stream(:templates, Admin.list(socket.assigns.staff_scope))}
  end
end
