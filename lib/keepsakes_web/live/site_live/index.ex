defmodule KeepsakesWeb.SiteLive.Index do
  @moduledoc """
  `/` on a customer's own domain: their name and the albums they chose to
  show (`Keepsakes.Domains.site_albums/1`). Each album opens its guest
  access page at `/<album>`; codes still apply. Drawn in the system
  default template's colours.
  """
  use KeepsakesWeb, :live_view

  alias Keepsakes.{Domains, Templates}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:guest}>
      <main id="site" class="mx-auto flex min-h-screen max-w-4xl flex-col gap-10 px-4 py-16 sm:px-8">
        <header class="flex flex-col items-center gap-2 text-center">
          <p class="font-hand text-2xl text-ks-guest-text">The albums of</p>
          <h1 class="font-display text-4xl font-bold text-ks-guest-ink sm:text-5xl">
            {@site_owner.first_name}{if @site_owner.last_name, do: " " <> @site_owner.last_name}
          </h1>
        </header>

        <p :if={@albums == []} id="site-empty" class="text-center text-ks-guest-text">
          Nothing to see here yet.
        </p>

        <ul :if={@albums != []} id="site-albums" class="grid gap-5 sm:grid-cols-2">
          <li :for={album <- @albums} id={"site-album-#{album.id}"}>
            <.link
              navigate={"/" <> album.slug}
              class="group flex h-full flex-col gap-2 rounded-box border border-ks-guest-line bg-ks-guest-card p-6 text-ks-guest-ink no-underline transition hover:-translate-y-0.5"
            >
              <span class="font-display text-2xl font-bold">{album.name}</span>
              <span :if={album.description} class="text-[15px] text-ks-guest-text">{album.description}</span>
              <span class="mt-auto flex items-center gap-1.5 pt-3 text-sm font-bold text-primary">
                Open with your code
                <.icon name="hero-arrow-right" class="size-4 transition group-hover:translate-x-0.5" />
              </span>
            </.link>
          </li>
        </ul>

        <p class="mt-auto text-center text-xs text-ks-guest-text">Made with Keepsake</p>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    owner = socket.assigns.site_owner

    {:ok,
     socket
     |> assign(page_title: "#{owner.first_name}'s albums", albums: Domains.site_albums(owner))
     |> assign(KeepsakesWeb.Templates.assigns(Templates.system_default()))}
  end
end
