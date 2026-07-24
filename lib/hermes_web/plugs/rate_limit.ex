defmodule HermesWeb.Plugs.RateLimit do
  @moduledoc """
  Fixed-window rate limiting for the token-authenticated API/MCP surface.

  Runs *before* `ApiAuth` so that credential-guessing (many requests with bad
  tokens) is throttled too. The rate key is the presented bearer token when one
  is sent, otherwise the caller's remote IP — so a single client cannot dodge
  the limit by omitting or rotating between blank tokens.

  On limit a `429 Too Many Requests` is returned with a `Retry-After` header.
  Limits are read from application config:

      config :hermes, HermesWeb.Plugs.RateLimit,
        limit: 60, window_ms: 60_000

  Disable entirely with `enabled: false` (used in tests that don't exercise it).
  """
  import Plug.Conn

  @default_limit 60
  @default_window_ms 60_000

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:hermes, __MODULE__, [])

    if Keyword.get(config, :enabled, true) do
      limit = Keyword.get(config, :limit, @default_limit)
      window_ms = Keyword.get(config, :window_ms, @default_window_ms)

      case Hermes.RateLimiter.hit(rate_key(conn), limit, window_ms) do
        :ok -> conn
        {:error, retry_after} -> too_many_requests(conn, retry_after)
      end
    else
      conn
    end
  end

  # Prefer the bearer token (identifies the caller even without a valid account);
  # fall back to remote IP for tokenless requests.
  defp rate_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when byte_size(token) > 0 -> {:token, hash(String.trim(token))}
      ["bearer " <> token | _] when byte_size(token) > 0 -> {:token, hash(String.trim(token))}
      _ -> {:ip, ip(conn)}
    end
  end

  # Hash the token so raw credentials never land in ETS keys.
  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  rescue
    _ -> "unknown"
  end

  defp too_many_requests(conn, retry_after) do
    body = Jason.encode!(%{error: %{code: "rate_limited", message: "Too many requests"}})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> send_resp(429, body)
    |> halt()
  end
end
