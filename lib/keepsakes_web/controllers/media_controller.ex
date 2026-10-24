defmodule KeepsakesWeb.MediaController do
  @moduledoc """
  Serves photos stored on local disk (`Keepsakes.Storage.Local`). The URL
  token is the authorisation: it names the key and expires on its own.

  With `x_accel_prefix` configured (production behind OpenResty), the app
  only checks the token and answers with an `X-Accel-Redirect` header;
  OpenResty then streams the file from an `internal` location, so Elixir
  never holds the bytes. Otherwise the file is sent directly.
  """
  use KeepsakesWeb, :controller

  alias Keepsakes.Storage
  alias Keepsakes.Storage.Local

  def show(conn, %{"token" => token}) do
    config = Application.fetch_env!(:keepsakes, Storage)

    with Local <- config[:adapter],
         {:ok, key} <- Local.verify_token(token),
         true <- Storage.exists?(key) do
      conn
      |> put_resp_content_type(MIME.from_path(key), nil)
      |> put_resp_header("cache-control", "private, max-age=3600, immutable")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> deliver(config, key)
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp deliver(conn, config, key) do
    case config[:x_accel_prefix] do
      nil ->
        send_file(conn, 200, Local.path(config, key))

      prefix ->
        conn
        |> put_resp_header("x-accel-redirect", Path.join(prefix, key))
        |> send_resp(200, "")
    end
  end
end
