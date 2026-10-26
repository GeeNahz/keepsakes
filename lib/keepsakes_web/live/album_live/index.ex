defmodule KeepsakesWeb.AlbumLive.Index do
  @moduledoc """
  `/app/albums`, the owner's home. With no albums it shows the "Start your
  first album" empty state (form events handled by `KeepsakesWeb.OwnerShell`);
  otherwise it opens the most recently created album.
  """
  use KeepsakesWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div id="albums-empty" class="flex flex-1 items-center justify-center">
        <div class="flex w-full max-w-[520px] flex-col items-center gap-7 text-center">
          <div class="relative h-[190px] w-[260px]" aria-hidden="true">
            <div class="absolute left-2.5 top-6 h-[150px] w-[130px] -rotate-9 rounded-md border-2 border-dashed border-ks-field">
            </div>
            <div class="absolute right-2.5 top-6 h-[150px] w-[130px] rotate-8 rounded-md border-2 border-dashed border-ks-field">
            </div>
            <div class="absolute left-[65px] top-1.5 flex h-40 w-[130px] -rotate-2 rounded-md bg-base-100 px-2.5 pb-[34px] pt-2.5 shadow-[0_12px_28px_rgba(27,30,39,0.14)] transition-transform duration-300 hover:-rotate-4">
              <div class="flex flex-1 items-center justify-center bg-ks-amber-soft">
                <.icon name="hero-plus" class="size-8 text-ks-amber-deep" />
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <h1 class="text-[34px] font-bold">Start your first album</h1>
            <p class="text-base leading-normal text-ks-muted">
              An album holds the photos for one story: a child growing up, a trip, a wedding.
              Give it a name to begin.
            </p>
          </div>

          <.form
            for={@owner.new_album_form}
            id="first-album-form"
            phx-change="new_album_validate"
            phx-submit="new_album_create"
            class="flex w-full flex-col gap-3 text-left"
          >
            <label for="first-album-name" class="text-sm font-bold">Album name</label>
            <div class="flex flex-col gap-2.5 sm:flex-row sm:items-start">
              <div class="min-w-0 flex-1 [&_.fieldset]:mb-0">
                <.input
                  field={@owner.new_album_form[:name]}
                  id="first-album-name"
                  placeholder="e.g. Our Little One"
                  maxlength="80"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </div>
              <.button
                id="first-album-submit"
                variant="primary"
                size="lg"
                class="whitespace-nowrap"
                phx-disable-with="Creating…"
              >
                Create album
              </.button>
            </div>
          </.form>

          <ol class="flex w-full justify-between gap-3 rounded-box border border-base-300 bg-base-100 px-6 py-5 text-left">
            <li :for={{n, title, text} <- steps()} class="flex flex-col gap-1 text-sm">
              <span class="font-mono text-ks-amber-deep">{n}</span>
              <span class="font-bold">{title}</span>
              <span class="text-ks-muted">{text}</span>
            </li>
          </ol>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case List.last(socket.assigns.owner.albums) do
      nil -> {:ok, assign(socket, page_title: "My albums")}
      album -> {:ok, push_navigate(socket, to: ~p"/app/albums/#{album.slug}")}
    end
  end

  defp steps do
    [
      {"01", "Create", "Name your album"},
      {"02", "Upload", "Add photos + details"},
      {"03", "Share", "Send link + code"}
    ]
  end
end
