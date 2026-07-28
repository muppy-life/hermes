defmodule HermesWeb.Api.FallbackController do
  @moduledoc """
  Translates `{:error, reason}` tuples returned by `Hermes.MCP.Tools` handlers
  into JSON HTTP error responses.
  """
  use HermesWeb, :controller

  def call(conn, {:error, :unauthenticated}) do
    error(conn, :unauthorized, "unauthorized", "Authentication required")
  end

  def call(conn, {:error, :not_found}) do
    error(conn, :not_found, "not_found", "Resource not found")
  end

  def call(conn, {:error, :unknown_tool}) do
    error(conn, :not_found, "unknown_tool", "Unknown operation")
  end

  def call(conn, {:error, {:invalid, message}}) do
    error(conn, :bad_request, "invalid_request", message)
  end

  def call(conn, {:error, {:unknown_value, field, suggestions}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "unknown_#{field}",
        message:
          "Unknown #{String.replace(field, "_", " ")}. Use an existing value or add it first.",
        suggestions: suggestions
      }
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Validation failed",
        details: translate_errors(changeset)
      }
    })
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
