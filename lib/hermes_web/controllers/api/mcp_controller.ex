defmodule HermesWeb.Api.MCPController do
  @moduledoc """
  Minimal MCP server over Streamable HTTP (JSON-RPC 2.0, POST only).

  Implements the handshake and tool-calling methods needed for a client like
  Claude to discover and invoke tech-ops tools:

    * `initialize`               -> server capabilities + info
    * `notifications/initialized`-> acknowledged (no response for notifications)
    * `ping`                     -> {}
    * `tools/list`               -> tool definitions from `Hermes.MCP.Tools`
    * `tools/call`               -> runs a tool, returns content blocks

  Auth is handled upstream by `HermesWeb.Plugs.ApiAuth`; `current_user` is
  assumed present. Tool results are returned as MCP `content` text blocks whose
  text is the JSON-encoded handler result, so clients can render or parse them.
  """
  use HermesWeb, :controller

  require Logger

  alias Hermes.MCP.Tools

  @protocol_version "2025-06-18"
  @server_info %{name: "hermes-tech-ops", version: "1.0.0"}

  # JSON-RPC error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  def handle(conn, _params) do
    case conn.body_params do
      # Batch request
      list when is_list(list) ->
        responses = list |> Enum.map(&dispatch(&1, conn)) |> Enum.reject(&is_nil/1)
        if responses == [], do: send_resp(conn, 202, ""), else: json(conn, responses)

      %{} = single ->
        case dispatch(single, conn) do
          nil -> send_resp(conn, 202, "")
          response -> json(conn, response)
        end

      _ ->
        json(conn, error_response(nil, @parse_error, "Parse error"))
    end
  end

  # Dispatch a single JSON-RPC message. Returns a response map, or nil for
  # notifications (no id) which must not produce a response body.
  defp dispatch(%{"jsonrpc" => "2.0", "method" => method} = msg, conn) do
    params = Map.get(msg, "params", %{})

    # A message without an "id" key is a notification: run side effects, no response.
    if Map.has_key?(msg, "id") do
      handle_method(method, params, Map.get(msg, "id"), conn)
    else
      handle_notification(method, params)
      nil
    end
  end

  defp dispatch(_invalid, _conn) do
    error_response(nil, @invalid_request, "Invalid Request")
  end

  defp handle_notification("notifications/initialized", _params), do: :ok
  defp handle_notification(_method, _params), do: :ok

  defp handle_method("initialize", _params, id, _conn) do
    result_response(id, %{
      protocolVersion: @protocol_version,
      capabilities: %{tools: %{}},
      serverInfo: @server_info
    })
  end

  defp handle_method("ping", _params, id, _conn), do: result_response(id, %{})

  defp handle_method("tools/list", _params, id, _conn) do
    tools =
      Enum.map(Tools.definitions(), fn tool ->
        %{
          name: tool.name,
          description: tool.description,
          inputSchema: tool.input_schema
        }
      end)

    result_response(id, %{tools: tools})
  end

  defp handle_method("tools/call", %{"name" => name} = params, id, conn) do
    args = Map.get(params, "arguments") || %{}
    user = conn.assigns.current_user

    try do
      case Tools.call(name, args, user) do
        {:ok, result} ->
          result_response(id, %{content: [text_content(result)], isError: false})

        {:error, reason} ->
          result_response(id, %{
            content: [text_content(%{error: error_text(reason)})],
            isError: true
          })
      end
    rescue
      e ->
        Logger.error("MCP tool #{name} crashed: #{Exception.message(e)}")
        error_response(id, @internal_error, "Tool execution failed")
    end
  end

  defp handle_method("tools/call", _params, id, _conn) do
    error_response(id, @invalid_params, "Missing tool name")
  end

  defp handle_method(_unknown, _params, id, _conn) do
    error_response(id, @method_not_found, "Method not found")
  end

  # --- helpers ---

  defp text_content(data) do
    %{type: "text", text: Jason.encode!(data)}
  end

  defp error_text(:not_found), do: "Resource not found"
  defp error_text(:unauthenticated), do: "Authentication required"
  defp error_text(:unknown_tool), do: "Unknown tool"
  defp error_text({:invalid, message}), do: message

  defp error_text({:unknown_value, field, suggestions}) do
    base =
      "Unknown #{String.replace(field, "_", " ")}. Use an existing value " <>
        "(see list_#{field}s) or add it first."

    case suggestions do
      [] -> base
      list -> base <> " Did you mean: " <> Enum.join(list, ", ") <> "?"
    end
  end

  defp error_text(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    "Validation failed: " <> Jason.encode!(errors)
  end

  defp error_text(other), do: inspect(other)

  defp result_response(id, result) do
    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp error_response(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
