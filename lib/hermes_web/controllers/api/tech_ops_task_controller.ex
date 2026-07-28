defmodule HermesWeb.Api.TechOpsTaskController do
  @moduledoc """
  REST endpoints for tech-ops tasks. All actions delegate to
  `Hermes.MCP.Tools` so the REST and MCP surfaces share one implementation.
  """
  use HermesWeb, :controller

  alias Hermes.MCP.Tools

  action_fallback HermesWeb.Api.FallbackController

  def index(conn, params) do
    args = Map.take(params, ["status"])

    with {:ok, %{tasks: tasks}} <-
           Tools.call("list_tech_ops_tasks", args, conn.assigns.current_user) do
      json(conn, %{data: tasks})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, task} <- Tools.call("get_tech_ops_task", %{"id" => id}, conn.assigns.current_user) do
      json(conn, %{data: task})
    end
  end

  def create(conn, params) do
    args = Map.take(params, ["reported_problem", "issue_origin", "reporter", "recorded_on"])

    with {:ok, task} <- Tools.call("report_tech_ops_task", args, conn.assigns.current_user) do
      conn
      |> put_status(:created)
      |> json(%{data: task})
    end
  end

  def update(conn, %{"id" => id} = params) do
    args =
      params
      |> Map.take(["status", "resolution", "issue_origin", "reporter"])
      |> Map.put("id", id)

    with {:ok, task} <- Tools.call("update_tech_ops_task", args, conn.assigns.current_user) do
      json(conn, %{data: task})
    end
  end
end
