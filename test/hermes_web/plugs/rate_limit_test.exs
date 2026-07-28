defmodule HermesWeb.Plugs.RateLimitTest do
  # async: false — mutates global app config and the shared rate-limiter table.
  use HermesWeb.ConnCase, async: false

  alias Hermes.Accounts

  setup %{conn: conn} do
    # Enable rate limiting with a tiny limit for this test only, and restore
    # the default (disabled in test) afterwards.
    previous = Application.get_env(:hermes, HermesWeb.Plugs.RateLimit)

    Application.put_env(:hermes, HermesWeb.Plugs.RateLimit,
      enabled: true,
      limit: 3,
      window_ms: 60_000
    )

    Hermes.RateLimiter.reset()

    on_exit(fn -> Application.put_env(:hermes, HermesWeb.Plugs.RateLimit, previous) end)

    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, dev} =
      Accounts.create_user(%{
        email: "dev@test.com",
        hashed_password: "h",
        role: "dev_team",
        team_id: team.id
      })

    {:ok, token, _} = Accounts.create_api_token(dev, "t")

    conn = put_req_header(conn, "accept", "application/json")
    %{conn: conn, token: token}
  end

  test "allows requests up to the limit then returns 429 with Retry-After", %{
    conn: conn,
    token: token
  } do
    auth = fn -> put_req_header(conn, "authorization", "Bearer " <> token) end

    for _ <- 1..3 do
      assert auth.() |> get(~p"/api/v1/me") |> json_response(200)
    end

    limited = auth.() |> get(~p"/api/v1/me")
    assert limited.status == 429
    assert Jason.decode!(limited.resp_body)["error"]["code"] == "rate_limited"
    assert [retry_after] = get_resp_header(limited, "retry-after")
    assert String.to_integer(retry_after) > 0
  end

  test "throttles credential-guessing before auth (bad tokens count)", %{conn: conn} do
    # Even invalid tokens are rate-limited: the plug runs before ApiAuth. Here
    # tokenless requests share the IP key and hit the limit.
    for _ <- 1..3, do: get(conn, ~p"/api/v1/me")
    limited = get(conn, ~p"/api/v1/me")
    assert limited.status == 429
  end

  test "rotating bearer tokens does not grant a fresh allowance (IP-keyed)", %{conn: conn} do
    # The limiter keys by IP, before auth, so an attacker cannot mint new
    # allowance by varying the Bearer value.
    for i <- 1..3 do
      conn |> put_req_header("authorization", "Bearer hermes_guess_#{i}") |> get(~p"/api/v1/me")
    end

    # A different (still invalid) token from the same IP is throttled, not reset.
    limited =
      conn |> put_req_header("authorization", "Bearer hermes_guess_4") |> get(~p"/api/v1/me")

    assert limited.status == 429
  end
end
