defmodule Keepsakes.RateLimitTest do
  use ExUnit.Case, async: true

  alias Keepsakes.RateLimit

  test "hit/3 allows up to the limit, then denies with a retry time" do
    key = "test:#{System.unique_integer([:positive])}"

    assert {:allow, 1} = RateLimit.hit(key, :timer.minutes(1), 2)
    assert {:allow, 2} = RateLimit.hit(key, :timer.minutes(1), 2)
    assert {:deny, retry_after} = RateLimit.hit(key, :timer.minutes(1), 2)
    assert retry_after > 0
  end

  test "check/3 is a no-op when disabled (the test env)" do
    key = "test:#{System.unique_integer([:positive])}"
    for _ <- 1..5, do: assert(:ok = RateLimit.check(key, :timer.minutes(1), 1))
  end

  test "AuthThrottle.message/1 rounds up to whole minutes" do
    assert KeepsakesWeb.AuthThrottle.message({:rate_limited, 30_000}) =~ "1 minute."
    assert KeepsakesWeb.AuthThrottle.message({:rate_limited, :timer.minutes(14)}) =~ "15 minutes."
  end
end
