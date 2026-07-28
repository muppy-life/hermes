defmodule Hermes.RateLimiterTest do
  # async: false — shares the single named ETS table owned by the app's
  # RateLimiter GenServer.
  use ExUnit.Case, async: false

  alias Hermes.RateLimiter

  setup do
    RateLimiter.reset()
    :ok
  end

  test "allows up to the limit within a window" do
    for _ <- 1..5 do
      assert RateLimiter.hit("k", 5, 60_000, 1_000) == :ok
    end
  end

  test "rejects once the limit is exceeded, with a retry-after" do
    for _ <- 1..5, do: RateLimiter.hit("k", 5, 60_000, 1_000)
    assert {:error, retry_after} = RateLimiter.hit("k", 5, 60_000, 1_000)
    assert retry_after > 0
    assert retry_after <= 60
  end

  test "keys are independent" do
    for _ <- 1..5, do: RateLimiter.hit("a", 5, 60_000, 1_000)
    assert {:error, _} = RateLimiter.hit("a", 5, 60_000, 1_000)
    # A different key still has its full allowance.
    assert RateLimiter.hit("b", 5, 60_000, 1_000) == :ok
  end

  test "the counter resets in the next window" do
    for _ <- 1..5, do: RateLimiter.hit("k", 5, 60_000, 1_000)
    assert {:error, _} = RateLimiter.hit("k", 5, 60_000, 1_000)

    # Advance past the window boundary (window = div(now, 60_000)).
    assert RateLimiter.hit("k", 5, 60_000, 61_000) == :ok
  end

  test "retry-after shrinks as the window nears its end" do
    now_ms = 30_000
    for _ <- 1..1, do: RateLimiter.hit("k", 1, 60_000, now_ms)
    {:error, retry_after} = RateLimiter.hit("k", 1, 60_000, now_ms)
    # Window ends at 60_000; ~30s remain.
    assert retry_after in 29..31
  end
end
