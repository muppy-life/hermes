defmodule HermesWeb.Api.RequestController do
  @moduledoc """
  Read-only REST endpoints for team requests. Visibility matches the app UI: a
  caller only sees requests where their team is the requesting or assigned team.
  Delegates to `Hermes.MCP.Tools` so REST and MCP share one implementation.
  """
  use HermesWeb, :controller

  alias Hermes.MCP.Tools

  action_fallback HermesWeb.Api.FallbackController

  def index(conn, params) do
    args = Map.take(params, ["status"])

    with {:ok, %{requests: requests}} <-
           Tools.call("list_requests", args, conn.assigns.current_user) do
      json(conn, %{data: requests})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, request} <- Tools.call("get_request", %{"id" => id}, conn.assigns.current_user) do
      json(conn, %{data: request})
    end
  end
end
