defmodule KeepsakesWeb.QrController do
  @moduledoc """
  `GET /app/albums/:slug/share/qr.png`: the album's share link as a QR code
  PNG, for the owner to put on their own designs. Owner only; the album
  must be shared.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.{Albums, Sharing}

  def show(conn, %{"slug" => slug}) do
    scope = conn.assigns.current_scope
    album = Albums.get_album_by_slug!(scope, slug)

    case Sharing.get_link(scope, album) do
      nil ->
        conn
        |> put_flash(:error, "Share the album first.")
        |> redirect(to: ~p"/app/albums/#{slug}/share")

      link ->
        png = link |> Sharing.url() |> EQRCode.encode() |> EQRCode.png(width: 1024)

        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{album.slug}-qr.png"))
        |> send_resp(200, png)
    end
  end
end
