defmodule HermesWeb.Plugs.VerifyGitHubSignature do
  @moduledoc """
  Verifies the `X-Hub-Signature-256` header against the raw request body
  using HMAC-SHA256 and the configured `GITHUB_WEBHOOK_SECRET`.

  Halts with 401 on missing or invalid signature.
  """

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    secret = Application.get_env(:hermes, :github, [])[:webhook_secret]
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()
    raw = conn.assigns[:raw_body]

    cond do
      is_nil(secret) or secret == "" ->
        Logger.warning("GitHub webhook rejected: GITHUB_WEBHOOK_SECRET not set")
        send_resp(conn, 503, "webhook not configured") |> halt()

      is_nil(signature) ->
        Logger.warning("GitHub webhook rejected: missing X-Hub-Signature-256")
        send_resp(conn, 401, "missing signature") |> halt()

      is_nil(raw) ->
        Logger.warning("GitHub webhook rejected: raw body not captured")
        send_resp(conn, 400, "no body") |> halt()

      not valid?(signature, raw, secret) ->
        Logger.warning("GitHub webhook rejected: signature mismatch")
        send_resp(conn, 401, "invalid signature") |> halt()

      true ->
        conn
    end
  end

  defp valid?("sha256=" <> hex, body, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(expected, hex)
  end

  defp valid?(_, _, _), do: false
end
