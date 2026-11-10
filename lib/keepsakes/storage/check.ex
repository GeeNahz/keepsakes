defmodule Keepsakes.Storage.Check do
  @moduledoc """
  End-to-end check of the configured storage: writes a small object, reads
  it back, signs a URL for it, fetches that URL (S3) or verifies its token
  (local disk), then deletes it.

  Used by `mix keepsakes.storage.check` and `Keepsakes.Release.storage_check/0`
  to confirm credentials before a deploy.
  """
  alias Keepsakes.Storage
  alias Keepsakes.Storage.{Local, S3}

  @type step :: {String.t(), :ok | {:error, term()}}

  @doc """
  Runs every step, stopping at the first failure. Returns the steps that ran.

  Options: `:req_options` merged into the signed-URL fetch (tests).
  """
  @spec run(keyword()) :: {:ok, [step]} | {:error, [step]}
  def run(opts \\ []) do
    key = "healthchecks/storage-check-#{System.system_time(:millisecond)}.txt"
    body = "keepsake storage check #{DateTime.utc_now()}"

    steps = [
      {"put #{key}", fn -> Storage.put(key, body, content_type: "text/plain") end},
      {"exists?", fn -> if Storage.exists?(key), do: :ok, else: {:error, :missing} end},
      {"get", fn -> expect_body(Storage.get(key), body) end},
      {"signed url", fn -> check_url(Storage.adapter(), key, body, opts) end},
      {"delete", fn -> Storage.delete(key) end}
    ]

    {status, done} =
      Enum.reduce_while(steps, {:ok, []}, fn {name, fun}, {:ok, acc} ->
        case fun.() do
          :ok -> {:cont, {:ok, [{name, :ok} | acc]}}
          error -> {:halt, {:error, [{name, normalize(error)} | acc]}}
        end
      end)

    # Don't leave the probe object behind when a later step failed
    if status == :error, do: Storage.delete(key)

    {status, Enum.reverse(done)}
  end

  @doc "One line per step, for printing."
  @spec format([step]) :: [String.t()]
  def format(steps) do
    Enum.map(steps, fn
      {name, :ok} -> "  ok    #{name}"
      {name, {:error, reason}} -> "  FAIL  #{name}: #{inspect(reason)}"
    end)
  end

  @doc "Adapter and (secret-free) target being checked, for printing."
  @spec describe() :: String.t()
  def describe do
    config = Application.fetch_env!(:keepsakes, Storage)

    case config[:adapter] do
      S3 -> "S3 bucket #{config[:bucket]} at #{config[:endpoint_url]}"
      Local -> "local disk at #{config[:root]}"
      other -> inspect(other)
    end
  end

  defp check_url(S3, key, body, opts) do
    url = Storage.url(key, expires_in: 60)

    case Req.get(url, Keyword.merge([retry: false, decode_body: false], opts[:req_options] || [])) do
      {:ok, %{status: 200, body: ^body}} -> :ok
      {:ok, %{status: 200}} -> {:error, :body_mismatch}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_url(Local, key, _body, _opts) do
    "/media/" <> token = Storage.url(key, expires_in: 60)

    case Local.verify_token(token) do
      {:ok, ^key} -> :ok
      other -> {:error, other}
    end
  end

  defp check_url(_adapter, _key, _body, _opts), do: :ok

  defp expect_body({:ok, body}, body), do: :ok
  defp expect_body({:ok, _other}, _body), do: {:error, :body_mismatch}
  defp expect_body(error, _body), do: error

  defp normalize({:error, _} = error), do: error
  defp normalize(other), do: {:error, other}
end
