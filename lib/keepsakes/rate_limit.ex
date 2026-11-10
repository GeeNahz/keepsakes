defmodule Keepsakes.RateLimit do
  @moduledoc """
  ETS-backed rate limiter (single node).

      case Keepsakes.RateLimit.check("access:\#{link_id}:\#{ip}", :timer.minutes(15), 5) do
        :ok -> ...
        {:error, {:rate_limited, retry_after_ms}} -> ...
      end

  `check/3` is a no-op when `config :keepsakes, Keepsakes.RateLimit, enabled: false`
  (the test env, where every request shares one IP). `hit/3` always counts.

  If the app ever runs on more than one node, switch the backend to
  `Hammer.Redis` so limits are shared.
  """
  use Hammer, backend: :ets

  @doc """
  Counts one hit for `key` and returns `:ok` while under `limit` hits per
  `scale` milliseconds.
  """
  def check(key, scale, limit) do
    if enabled?() do
      case hit(key, scale, limit) do
        {:allow, _count} -> :ok
        {:deny, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
      end
    else
      :ok
    end
  end

  defp enabled? do
    Application.get_env(:keepsakes, __MODULE__, [])[:enabled] != false
  end
end
