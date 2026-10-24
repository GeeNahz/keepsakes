defmodule Keepsakes.Storage.Local do
  @moduledoc """
  Stores objects on local disk under the configured `:root`.

  `url/3` returns `/media/<signed token>`; the media controller verifies
  the token with `verify_token/1` and serves the file (via OpenResty
  `X-Accel-Redirect` in production).
  """
  @behaviour Keepsakes.Storage

  @salt "storage.local.media"

  @impl true
  def put(config, key, {:file, source}, _opts) do
    path = path(config, key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, _} <- File.copy(source, path) do
      :ok
    end
  end

  def put(config, key, body, _opts) do
    path = path(config, key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, body)
    end
  end

  @impl true
  def get(config, key) do
    case File.read(path(config, key)) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(config, key) do
    case File.rm(path(config, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(config, key), do: File.regular?(path(config, key))

  @impl true
  def url(_config, key, opts) do
    signed_at = Keyword.get_lazy(opts, :signed_at, fn -> System.system_time(:second) end)
    expires_at = signed_at + Keyword.get(opts, :expires_in, 3600)

    token =
      Phoenix.Token.sign(KeepsakesWeb.Endpoint, @salt, {key, expires_at}, signed_at: signed_at)

    "/media/" <> token
  end

  @doc "Returns `{:ok, key}` for a valid, unexpired media token."
  @spec verify_token(String.t()) :: {:ok, Keepsakes.Storage.key()} | {:error, atom()}
  def verify_token(token) do
    case Phoenix.Token.verify(KeepsakesWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, {key, expires_at}} ->
        if System.system_time(:second) < expires_at, do: {:ok, key}, else: {:error, :expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Absolute path on disk for `key`."
  def path(config, key), do: Path.join(Keyword.fetch!(config, :root), key)
end
