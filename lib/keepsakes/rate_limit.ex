defmodule Keepsakes.RateLimit do
  @moduledoc """
  ETS-backed rate limiter (single node).

      case Keepsakes.RateLimit.hit("access:\#{link_id}:\#{ip}", :timer.minutes(15), 5) do
        {:allow, _count} -> ...
        {:deny, retry_after_ms} -> ...
      end

  If the app ever runs on more than one node, switch the backend to
  `Hammer.Redis` so limits are shared.
  """
  use Hammer, backend: :ets
end
