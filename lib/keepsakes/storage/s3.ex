defmodule Keepsakes.Storage.S3 do
  @moduledoc """
  S3-compatible object storage (Cloudflare R2, DigitalOcean Spaces, AWS S3)
  over `Req` + `ReqS3`. Objects stay private; reads go through presigned URLs.

  Config keys: `:bucket`, `:endpoint_url`, `:region`, `:access_key_id`,
  `:secret_access_key`, and optional `:req_options` (used by tests to plug
  in `Req.Test`).
  """
  @behaviour Keepsakes.Storage

  @impl true
  def put(config, key, {:file, source}, opts) do
    with {:ok, data} <- File.read(source), do: put(config, key, data, opts)
  end

  def put(config, key, body, opts) do
    headers =
      case Keyword.get(opts, :content_type) do
        nil -> []
        type -> [content_type: type]
      end

    case Req.put(req(config), url: object_url(config, key), body: body, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(config, key) do
    case Req.get(req(config), url: object_url(config, key), decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(config, key) do
    case Req.delete(req(config), url: object_url(config, key)) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      {:ok, response} -> {:error, {:http, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(config, key) do
    match?({:ok, %{status: 200}}, Req.head(req(config), url: object_url(config, key)))
  end

  @impl true
  def url(config, key, opts) do
    ReqS3.presign_url(
      bucket: Keyword.fetch!(config, :bucket),
      key: key,
      endpoint_url: Keyword.fetch!(config, :endpoint_url),
      region: Keyword.fetch!(config, :region),
      access_key_id: Keyword.fetch!(config, :access_key_id),
      secret_access_key: Keyword.fetch!(config, :secret_access_key),
      expires: Keyword.get(opts, :expires_in, 3600),
      datetime:
        opts
        |> Keyword.get_lazy(:signed_at, fn -> System.system_time(:second) end)
        |> DateTime.from_unix!()
    )
  end

  defp object_url(config, key), do: "s3://#{Keyword.fetch!(config, :bucket)}/#{key}"

  defp req(config) do
    options =
      Keyword.merge(
        [
          aws_sigv4: [
            access_key_id: Keyword.fetch!(config, :access_key_id),
            secret_access_key: Keyword.fetch!(config, :secret_access_key),
            region: Keyword.fetch!(config, :region)
          ],
          aws_endpoint_url_s3: Keyword.fetch!(config, :endpoint_url),
          retry: :transient
        ],
        Keyword.get(config, :req_options, [])
      )

    # ReqS3 registers :aws_endpoint_url_s3, so options go through attach/2.
    ReqS3.attach(Req.new(), options)
  end
end
