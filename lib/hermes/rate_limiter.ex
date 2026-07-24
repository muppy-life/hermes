defmodule Hermes.RateLimiter do
  @moduledoc """
  A lightweight in-memory (ETS) fixed-window rate limiter.

  A single GenServer owns a public ETS table and periodically sweeps expired
  windows so the table cannot grow unbounded. The increment itself runs in the
  caller process via `:ets.update_counter/4` (lock-free), so the GenServer is
  not in the request hot path.

  This is per-node. Behind multiple app instances each node enforces the limit
  independently; for API/MCP abuse prevention that is acceptable, and an
  edge/LB limiter should be the outer defense. No external dependency.

  Each ETS row is `{{key, window}, count, expires_at_ms}`: the counter lives at
  position 2 and the window's absolute expiry at position 3, which the sweep
  uses to drop stale rows regardless of window size.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(1)

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a hit for `key` and reports whether it is within the limit.

  Returns `:ok` when allowed, or `{:error, retry_after_seconds}` when the limit
  for the current window is exceeded.

  * `limit` — max requests allowed per window
  * `window_ms` — window length in milliseconds
  * `now_ms` — current time (injectable for tests)
  """
  def hit(key, limit, window_ms, now_ms \\ System.system_time(:millisecond)) do
    window = div(now_ms, window_ms)
    window_end_ms = (window + 1) * window_ms
    row_key = {key, window}

    # Create the row (count 0, with this window's expiry) if absent, then
    # atomically bump the counter at position 2.
    count =
      :ets.update_counter(@table, row_key, {2, 1}, {row_key, 0, window_end_ms})

    if count <= limit do
      :ok
    else
      retry_after = max(1, ceil((window_end_ms - now_ms) / 1000))
      {:error, retry_after}
    end
  end

  @doc "Clears all counters. Test helper."
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  ## Server

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    # Delete rows whose window has already ended (expiry at position 3 < now).
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
