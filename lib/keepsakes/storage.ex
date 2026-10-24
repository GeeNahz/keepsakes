defmodule Keepsakes.Storage do
  @moduledoc """
  Object storage for photos and attachments.

  The adapter is chosen from config (see `config/runtime.exs`):

    * `Keepsakes.Storage.S3` when `S3_BUCKET` is set (Cloudflare R2,
      DigitalOcean Spaces or any S3-compatible service)
    * `Keepsakes.Storage.Local` otherwise (local disk; dev, test and the
      VPS fallback)

  Keys are relative paths such as `"users/<uuid>/memories/<uuid>/w2400.webp"`.
  Objects are private; read them through `url/2`, which returns a
  short-lived signed URL.
  """

  @type key :: String.t()
  @type body :: iodata() | {:file, Path.t()}
  @type config :: keyword()

  @callback put(config, key, body, opts :: keyword()) :: :ok | {:error, term()}
  @callback get(config, key) :: {:ok, binary()} | {:error, :not_found | term()}
  @callback delete(config, key) :: :ok | {:error, term()}
  @callback exists?(config, key) :: boolean()
  @callback url(config, key, opts :: keyword()) :: String.t()

  @key_format ~r/\A[A-Za-z0-9_\-\.]+(\/[A-Za-z0-9_\-\.]+)*\z/

  @doc "Stores `body` under `key`. Options: `:content_type`."
  @spec put(key, body, keyword()) :: :ok | {:error, term()}
  def put(key, body, opts \\ []), do: with_key(key, &adapter().put(config(), &1, body, opts))

  @spec get(key) :: {:ok, binary()} | {:error, :not_found | term()}
  def get(key), do: with_key(key, &adapter().get(config(), &1))

  @spec delete(key) :: :ok | {:error, term()}
  def delete(key), do: with_key(key, &adapter().delete(config(), &1))

  @spec exists?(key) :: boolean()
  def exists?(key), do: valid_key?(key) and adapter().exists?(config(), key)

  @doc "Signed URL for `key`. Options: `:expires_in` seconds (default 3600)."
  @spec url(key, keyword()) :: String.t()
  def url(key, opts \\ []) do
    unless valid_key?(key), do: raise(ArgumentError, "invalid storage key: #{inspect(key)}")
    adapter().url(config(), key, opts)
  end

  @doc "Keys may only contain `[A-Za-z0-9_-.]` segments separated by `/`, never `..`."
  @spec valid_key?(term()) :: boolean()
  def valid_key?(key) when is_binary(key) do
    Regex.match?(@key_format, key) and ".." not in String.split(key, "/")
  end

  def valid_key?(_), do: false

  @doc "The configured adapter module."
  def adapter, do: Keyword.fetch!(config(), :adapter)

  defp config, do: Application.fetch_env!(:keepsakes, __MODULE__)

  defp with_key(key, fun) do
    if valid_key?(key), do: fun.(key), else: {:error, :invalid_key}
  end
end
