defmodule HermesWeb.Api.IssueOriginController do
  @moduledoc """
  Canonical issue-origin lookup values. `index` lists them; `create` adds one
  (idempotent, normalized). Delegates to `Hermes.MCP.Tools` so REST and MCP
  share one implementation.
  """
  use HermesWeb, :controller

  alias Hermes.MCP.Tools

  action_fallback HermesWeb.Api.FallbackController

  def index(conn, _params) do
    with {:ok, %{issue_origins: origins}} <-
           Tools.call("list_issue_origins", %{}, conn.assigns.current_user) do
      json(conn, %{data: origins})
    end
  end

  def create(conn, params) do
    args = Map.take(params, ["name"])

    with {:ok, origin} <- Tools.call("add_issue_origin", args, conn.assigns.current_user) do
      conn |> put_status(:created) |> json(%{data: origin})
    end
  end
end
