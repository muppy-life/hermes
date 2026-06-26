defmodule Hermes.Services.Claude do
  @moduledoc """
  Deprecated. Use `Hermes.Services.LLM` instead.

  This module is a thin backward-compatible shim over the provider-agnostic
  `Hermes.Services.LLM` facade, which dispatches to the configured adapter
  (Anthropic, OpenRouter, or an in-memory fake). New code should call
  `Hermes.Services.LLM` directly.
  """

  alias Hermes.Services.LLM

  @deprecated "Use Hermes.Services.LLM.complete/2"
  def send_message(messages, opts \\ []) do
    case LLM.complete(messages, opts) do
      {:ok, %LLM.Response{raw: raw}} -> {:ok, raw}
      {:error, reason} -> {:error, legacy_error(reason)}
    end
  end

  @deprecated "Use Hermes.Services.LLM.ask/2"
  def ask(prompt, opts \\ []) do
    prompt |> LLM.ask(opts) |> wrap_error()
  end

  @deprecated "Use Hermes.Services.LLM.chat/2"
  def chat(conversation, opts \\ []) do
    conversation |> LLM.chat(opts) |> wrap_error()
  end

  defp wrap_error({:ok, _} = ok), do: ok
  defp wrap_error({:error, reason}), do: {:error, legacy_error(reason)}

  # Preserve the historical string error so existing callers/pattern matches
  # keep working.
  defp legacy_error(:missing_api_key), do: "ANTHROPIC_API_KEY not configured"

  defp legacy_error({:http_status, status, body}),
    do: "API request failed with status #{status}: #{inspect(body)}"

  defp legacy_error({:transport, reason}), do: "HTTP request failed: #{inspect(reason)}"
  defp legacy_error(other), do: inspect(other)
end
