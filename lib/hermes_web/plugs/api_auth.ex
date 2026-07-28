defmodule HermesWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates API/MCP requests via a personal API token.

  Expects an `Authorization: Bearer <token>` header. On success assigns
  `:current_user`. Access is restricted to the tech team (dev_team or admin),
  matching the tech-ops view. Failures return a JSON error with the right
  status; MCP endpoints wrap this in a JSON-RPC envelope at the controller
  layer, but a 401 before dispatch is a valid transport-level response.
  """
  import Plug.Conn

  alias Hermes.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- fetch_bearer_token(conn),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token),
         true <- Accounts.is_dev_team?(user) do
      assign(conn, :current_user, user)
    else
      false -> send_error(conn, 403, "forbidden", "API access is restricted to the tech team")
      nil -> send_error(conn, 401, "unauthorized", "Invalid or expired API token")
      :error -> send_error(conn, 401, "unauthorized", "Missing bearer token")
    end
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> validate_token(token)
      ["bearer " <> token | _] -> validate_token(token)
      _ -> :error
    end
  end

  # Treat an empty/whitespace-only bearer value as a missing token instead of
  # querying the DB with a blank string.
  defp validate_token(token) do
    case String.trim(token) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp send_error(conn, status, code, message) do
    body = Jason.encode!(%{error: %{code: code, message: message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end
end
