defmodule HermesWeb.RawBodyReader do
  @moduledoc """
  Plug body reader that caches the raw request body on the conn for paths
  that need HMAC signature verification (currently the GitHub webhook).

  Stored on `conn.assigns[:raw_body]` only for paths under `/api/github/`
  to avoid bloating memory on every request.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, maybe_stash(conn, body)}
      {:more, body, conn} -> {:more, body, maybe_stash(conn, body)}
      {:error, _} = err -> err
    end
  end

  defp maybe_stash(%Plug.Conn{request_path: "/api/github/" <> _} = conn, body) do
    existing = conn.assigns[:raw_body] || ""
    Plug.Conn.assign(conn, :raw_body, existing <> body)
  end

  defp maybe_stash(conn, _body), do: conn
end
