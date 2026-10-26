defmodule KeepsakesWeb.DataExportController do
  @moduledoc """
  `GET /app/settings/privacy/exports/:id`: the link in the "export is
  ready" email. Checks it's the owner's and still within its 7 days, then
  sends them to a short-lived storage URL for the zip.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.{Exports, Storage}

  def show(conn, %{"id" => id}) do
    case Exports.get_downloadable(conn.assigns.current_scope, id) do
      nil ->
        conn
        |> put_flash(:error, "That export has expired. You can make a new one here.")
        |> redirect(to: ~p"/app/settings/privacy")

      export ->
        redirect(conn, external: absolute(Storage.url(export.storage_key, expires_in: 600)))
    end
  end

  # Local storage gives a path (/media/...); S3 a full URL
  defp absolute("/" <> _ = path), do: KeepsakesWeb.Endpoint.url() <> path
  defp absolute(url), do: url
end
