defmodule KeepsakesWeb.AlbumLive.Card do
  @moduledoc """
  `/app/albums/:slug/share/card`: a printable card with the album's QR
  code, for a wedding table, a fridge or a gift. The browser prints it (or
  saves it as a PDF); the QR code alone downloads as a PNG
  (`KeepsakesWeb.QrController`).

  The code is left off unless the owner chooses to print it. With guest
  uploads on, a second card points straight at the "Add your photos" page.
  Owner only, and only for shared albums.
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.MemoryComponents, only: [photo: 1]

  alias Keepsakes.{Albums, Sharing}
  alias Keepsakes.Sharing.Engagement
  alias KeepsakesWeb.OwnerShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} owner={@owner}>
      <div class="mx-auto flex w-full max-w-[860px] flex-col gap-6">
        <div class="flex flex-col gap-1.5 print:hidden">
          <.link
            id="card-back"
            navigate={~p"/app/albums/#{@album.slug}/share"}
            class="w-fit text-sm font-medium no-underline"
          >
            ← Share settings
          </.link>
          <h1 class="text-[32px] font-bold">QR card</h1>
          <p class="text-ks-muted">
            Print it, or choose “Save as PDF” in the print window. Guests scan the code with their phone camera.
          </p>
          <form id="card-options" phx-change="options" class="flex flex-wrap items-center gap-5 pt-2">
            <label class="flex cursor-pointer items-center gap-2 text-[15px]">
              <input type="hidden" name="show_code" value="false" />
              <input
                type="checkbox"
                name="show_code"
                value="true"
                checked={@show_code?}
                class="toggle toggle-primary toggle-sm"
              /> Print the access code on the card
            </label>
          </form>
          <div class="flex flex-wrap gap-2.5 pt-2">
            <.button id="card-print" variant="primary" phx-click={JS.dispatch("ks:print")}>
              <.icon name="hero-printer" class="size-4" /> Print
            </.button>
            <.button id="card-download-qr" href={~p"/app/albums/#{@album.slug}/share/qr.png"}>
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download QR (PNG)
            </.button>
          </div>
        </div>

        <.card
          id="qr-card"
          album={@album}
          cover={@cover}
          svg={@view_svg}
          url={@view_url}
          heading={@album.name}
          message="Scan to open our album"
          code={@show_code? && @link.code}
        />

        <.card
          :if={@add_svg}
          id="qr-card-add"
          album={@album}
          cover={nil}
          svg={@add_svg}
          url={@add_url}
          heading="Add your photos"
          message={"Scan to share your photos of #{@album.name}"}
          code={@show_code? && @link.code}
        />
      </div>
      <div id="card-print-hook" phx-hook=".Print" class="hidden"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Print">
        export default {
          mounted() {
            this.onPrint = () => window.print()
            window.addEventListener("ks:print", this.onPrint)
          },
          destroyed() { window.removeEventListener("ks:print", this.onPrint) }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :album, :map, required: true
  attr :cover, :any, required: true
  attr :svg, :string, required: true
  attr :url, :string, required: true
  attr :heading, :string, required: true
  attr :message, :string, required: true
  attr :code, :any, default: false

  defp card(assigns) do
    ~H"""
    <article
      id={@id}
      class="mx-auto flex w-full max-w-[420px] break-inside-avoid flex-col items-center gap-4 rounded-2xl border border-base-300 bg-white p-8 text-center text-ks-ink shadow-sm print:my-6 print:shadow-none"
    >
      <div :if={@cover} class="h-[150px] w-full overflow-hidden rounded-box">
        <.photo memory={@cover} width={1200} alt="" class="size-full" />
      </div>
      <h2 class="font-hand text-[40px] leading-none">{@heading}</h2>
      <p class="text-[15px] text-ks-muted">{@message}</p>
      <div class="size-[220px] [&_svg]:size-full" aria-label="QR code">{Phoenix.HTML.raw(@svg)}</div>
      <p class="break-all font-mono text-sm">{@url}</p>
      <p :if={@code} class="text-[15px]">
        Access code <span class="font-mono text-lg font-bold tracking-[0.2em]">{@code}</span>
      </p>
      <span class="text-xs text-ks-muted">Made with Keepsake</span>
    </article>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    album = Albums.get_album_by_slug!(scope, slug)

    case Sharing.get_link(scope, album) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Share the album first to make a QR card.")
         |> push_navigate(to: ~p"/app/albums/#{album.slug}/share")}

      link ->
        link = %{link | album: album, user: scope.user}
        view_url = Sharing.url(link)
        add_url = Engagement.uploads_open?(link) && view_url <> "/add"

        {:ok,
         socket
         |> OwnerShell.put_current_album(album.id)
         |> assign(
           page_title: "QR card · #{album.name}",
           album: album,
           link: link,
           cover: cover(scope, album),
           show_code?: false,
           view_url: Sharing.display_url(link),
           view_svg: qr_svg(view_url),
           add_url: add_url && String.replace(add_url, ~r{\Ahttps?://}, ""),
           add_svg: add_url && qr_svg(add_url)
         )}
    end
  end

  @impl true
  def handle_event("options", params, socket),
    do: {:noreply, assign(socket, show_code?: params["show_code"] == "true")}

  @doc "The QR code for `url` as an inline SVG."
  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 220)

  defp cover(_scope, %{cover_memory_id: nil}), do: nil

  defp cover(scope, album) do
    Albums.get_memory!(scope, album, album.cover_memory_id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
