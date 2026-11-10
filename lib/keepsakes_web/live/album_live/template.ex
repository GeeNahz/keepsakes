defmodule KeepsakesWeb.AlbumLive.Template do
  @moduledoc """
  `/app/albums/:slug/template`: the template gallery for one album. Each card
  shows the template in its own colours with the album's photos; Preview
  opens the album in that template (`/a/preview/:slug/:template/timeline`)
  before anything changes, and "Use this template" switches what guests
  see straight away. Premium templates offer an upgrade instead when the
  plan doesn't include them (preview still works).
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.TemplateComponents

  alias Keepsakes.{Albums, Sharing, Templates}
  alias KeepsakesWeb.{GuestComponents, OwnerShell}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[1040px] flex-col gap-6">
        <div class="flex flex-col gap-1.5">
          <.link
            id="template-back"
            navigate={~p"/app/albums/#{@album.slug}"}
            class="w-fit text-sm font-medium no-underline"
          >
            ← {@album.name}
          </.link>
          <h1 class="text-[32px] font-bold">Choose a template</h1>
          <p class="text-base text-ks-muted">
            A template sets how guests see this album: the code page, the timeline and the slideshow. Your photos and details stay the same.
          </p>
        </div>

        <div
          id="template-gallery"
          class="grid gap-5 [grid-template-columns:repeat(auto-fill,minmax(280px,1fr))]"
        >
          <.template_card
            :for={template <- @templates}
            id={"template-#{template.slug}"}
            template={template}
            current={template.id == @current.id}
            title={@album.name}
            photos={@photos}
          >
            <:actions>
              <.button
                id={"preview-#{template.slug}"}
                href={~p"/a/preview/#{@album.slug}/#{template.slug}/timeline"}
              >
                <.icon name="hero-eye" class="size-[18px]" /> Preview
              </.button>
              <%= cond do %>
                <% template.id == @current.id -> %>
                <% template.premium and not @premium? -> %>
                  <.button
                    id={"upgrade-#{template.slug}"}
                    variant="primary"
                    navigate={~p"/app/settings/billing"}
                  >
                    Upgrade to use
                  </.button>
                <% true -> %>
                  <.button
                    id={"use-#{template.slug}"}
                    variant="primary"
                    phx-click="use"
                    phx-value-slug={template.slug}
                  >
                    Use this template
                  </.button>
              <% end %>
            </:actions>
          </.template_card>
          <.create_your_own_card id="create-template" />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    album = Albums.get_album_by_slug!(scope, slug)

    photos =
      album
      |> Sharing.guest_memories()
      |> Enum.take(2)
      |> Enum.map(&GuestComponents.photo_url(&1, 480))

    {:ok,
     socket
     |> OwnerShell.put_current_album(album.id)
     |> assign(
       page_title: "Template · #{album.name}",
       album: album,
       photos: photos,
       templates: Templates.list_templates(scope),
       current: Templates.for_album(album),
       premium?: Templates.premium?(scope)
     )}
  end

  @impl true
  def handle_event("use", %{"slug" => slug}, socket) do
    %{current_scope: scope, album: album} = socket.assigns

    with %{} = template <- Templates.get_template(scope, slug),
         {:ok, album} <- Templates.set_album_template(scope, album, template) do
      {:noreply,
       socket
       |> assign(album: album, current: template)
       |> put_flash(:info, "Guests now see this album in #{template.name}.")}
    else
      {:error, :premium} ->
        {:noreply, put_flash(socket, :error, "Premium templates need the Plus or Pro plan.")}

      _ ->
        {:noreply, put_flash(socket, :error, "That template isn't available.")}
    end
  end
end
