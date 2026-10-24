defmodule KeepsakesWeb.Dev.ComponentsLive do
  @moduledoc """
  Dev-only component gallery (`/dev/components`) for checking the themed
  core components against the design canvas, in both themes.
  """
  use KeepsakesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"name" => "", "email" => "", "month" => "", "caption" => ""}, as: :demo)
    {:ok, assign(socket, page_title: "Components", form: form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Component gallery
        <:subtitle>Core components in the keepsake theme. Toggle the theme in the header.</:subtitle>
      </.header>

      <div class="flex flex-col gap-10">
        <section id="gallery-buttons" class="flex flex-col gap-3">
          <h2 class="text-xl font-bold">Buttons</h2>
          <div class="flex flex-wrap gap-2.5">
            <.button variant="primary">Create album</.button>
            <.button variant="secondary">Bulk upload</.button>
            <.button variant="outline">Upload one</.button>
            <.button>Preview as guest</.button>
            <.button variant="danger">Turn off sharing</.button>
            <.button variant="primary" disabled>Share album</.button>
            <.button variant="primary" size="lg">Create account</.button>
          </div>
        </section>

        <section id="gallery-badges" class="flex flex-col gap-3">
          <h2 class="text-xl font-bold">Badges, avatar, logo</h2>
          <div class="flex flex-wrap items-center gap-3">
            <.badge>Cover</.badge>
            <.badge variant="ready">Ready</.badge>
            <.badge variant="pending">Needs date</.badge>
            <.badge variant="muted">Draft</.badge>
            <.avatar name="Godswill Nasara" />
            <.logo />
          </div>
        </section>

        <section id="gallery-meter" class="flex max-w-60 flex-col gap-3">
          <h2 class="text-xl font-bold">Meter</h2>
          <.meter id="gallery-storage" label="Storage" value={38} max={1024} text="38 MB of 1 GB" />
        </section>

        <section id="gallery-form" class="flex max-w-md flex-col gap-3">
          <h2 class="text-xl font-bold">Form fields</h2>
          <.form for={@form} id="gallery-demo-form">
            <.input field={@form[:name]} label="Full name" placeholder="Godswill Nasara" />
            <.input field={@form[:email]} type="email" label="Email" placeholder="you@example.com" />
            <.input
              field={@form[:month]}
              type="select"
              label="Month"
              prompt="Month"
              options={~w(January February March April)}
            />
            <.input
              field={@form[:caption]}
              type="textarea"
              label="Caption"
              placeholder="What was happening?"
            />
            <.input name="demo[cover]" type="checkbox" label="Use as album cover" value={false} />
          </.form>
        </section>

        <section id="gallery-modal" class="flex flex-col gap-3">
          <h2 class="text-xl font-bold">Modal</h2>
          <div>
            <.button id="gallery-open-modal" phx-click={show_modal("gallery-new-album")}>
              <.icon name="hero-plus" class="size-4" /> New album
            </.button>
          </div>
          <.modal
            id="gallery-new-album"
            title="New album"
            subtitle="One album per story — you can add photos next."
          >
            <.input name="album_name" label="Album name" value="" placeholder="e.g. Lagos Trip 2023" />
            <div class="flex justify-end gap-2.5">
              <.button phx-click={hide_modal("gallery-new-album")}>Cancel</.button>
              <.button variant="primary">Create album</.button>
            </div>
          </.modal>
        </section>

        <section
          id="gallery-night"
          data-theme="keepsake-night"
          class="flex flex-col gap-3 rounded-box bg-base-200 p-6 text-base-content"
        >
          <h2 class="text-xl font-bold">keepsake-night (guest)</h2>
          <p class="text-ks-night-text">Every memory, in the order it happened.</p>
          <div class="flex flex-wrap gap-2.5">
            <.button variant="primary">Open album</.button>
            <.button>Play as slideshow</.button>
          </div>
          <p class="font-mono text-sm text-ks-night-text">April 2019</p>
          <p class="font-hand text-2xl">First birthday</p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
