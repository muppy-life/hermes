defmodule HermesWeb.Api.ReporterController do
  @moduledoc """
  Canonical reporter lookup values. `index` lists them; `create` adds one
  (idempotent, normalized). Delegates to `Hermes.MCP.Tools` so REST and MCP
  share one implementation.
  """
  use HermesWeb, :controller

  alias Hermes.MCP.Tools

  action_fallback HermesWeb.Api.FallbackController

  def index(conn, _params) do
    with {:ok, %{reporters: reporters}} <-
           Tools.call("list_reporters", %{}, conn.assigns.current_user) do
      json(conn, %{data: reporters})
    end
  end

  def create(conn, params) do
    args = Map.take(params, ["name"])

    with {:ok, reporter} <- Tools.call("add_reporter", args, conn.assigns.current_user) do
      conn |> put_status(:created) |> json(%{data: reporter})
    end
  end
end
