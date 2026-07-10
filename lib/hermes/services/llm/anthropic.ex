defmodule Hermes.Services.LLM.Anthropic do
  @moduledoc """
  LLM adapter for the Anthropic Messages API (`/v1/messages`).

  Config (all optional except the key):

      config :hermes, :llm,
        anthropic: [
          api_key: System.get_env("ANTHROPIC_API_KEY"),
          api_url: "https://api.anthropic.com/v1/messages",
          api_version: "2023-06-01"
        ]

  The API key also falls back to the `ANTHROPIC_API_KEY` env var.
  """

  @behaviour Hermes.Services.LLM.Adapter

  alias Hermes.Services.LLM.{HTTP, Request, Response}

  @default_url "https://api.anthropic.com/v1/messages"
  @default_version "2023-06-01"

  @impl true
  def complete(%Request{} = request) do
    case api_key() do
      key when key in [nil, ""] ->
        {:error, :missing_api_key}

      key ->
        headers = [
          {"x-api-key", key},
          {"anthropic-version", api_version()},
          {"content-type", "application/json"}
        ]

        opts =
          [url: api_url(), json: build_body(request), headers: headers]
          |> HTTP.maybe_put_test_options()

        case Req.post(opts) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            parse(body, request)

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_status, status, body}}

          {:error, reason} ->
            {:error, {:transport, reason}}
        end
    end
  end

  defp build_body(%Request{} = r) do
    body = %{
      "model" => r.model,
      "max_tokens" => r.max_tokens,
      "temperature" => r.temperature,
      "messages" => Enum.map(r.messages, &%{"role" => &1.role, "content" => &1.content})
    }

    if r.system, do: Map.put(body, "system", r.system), else: body
  end

  defp parse(%{"content" => content} = body, _request) when is_list(content) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", & &1["text"])

    {:ok,
     %Response{
       text: text,
       model: body["model"],
       finish_reason: body["stop_reason"],
       usage: usage(body["usage"]),
       raw: body
     }}
  end

  defp parse(body, _request), do: {:error, {:unexpected_response, body}}

  defp usage(%{"input_tokens" => input, "output_tokens" => output}) do
    %{input_tokens: input, output_tokens: output}
  end

  defp usage(_), do: nil

  defp api_key do
    config()[:api_key] || System.get_env("ANTHROPIC_API_KEY")
  end

  defp api_url, do: config()[:api_url] || @default_url
  defp api_version, do: config()[:api_version] || @default_version

  defp config, do: Application.get_env(:hermes, :llm, [])[:anthropic] || []
end
