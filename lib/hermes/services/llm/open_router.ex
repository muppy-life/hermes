defmodule Hermes.Services.LLM.OpenRouter do
  @moduledoc """
  LLM adapter for [OpenRouter](https://openrouter.ai), which exposes an
  OpenAI-compatible chat-completions API (`/api/v1/chat/completions`).

  One key reaches every model OpenRouter fronts (Anthropic, OpenAI, Google,
  Mistral, …); pick the model with a namespaced id like
  `"anthropic/claude-sonnet-4"` or `"openai/gpt-4o"`.

  Config (all optional except the key):

      config :hermes, :llm,
        openrouter: [
          api_key: System.get_env("OPENROUTER_API_KEY"),
          api_url: "https://openrouter.ai/api/v1/chat/completions",
          # Optional attribution headers used by OpenRouter rankings:
          referer: "https://muppy.com",
          title: "Hermes"
        ]

  The API key also falls back to the `OPENROUTER_API_KEY` env var.
  """

  @behaviour Hermes.Services.LLM.Adapter

  alias Hermes.Services.LLM.{HTTP, Request, Response}

  @default_url "https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def complete(%Request{} = request) do
    case api_key() do
      key when key in [nil, ""] ->
        {:error, :missing_api_key}

      key ->
        opts =
          [url: api_url(), json: build_body(request), headers: headers(key)]
          |> HTTP.maybe_put_test_options()

        case Req.post(opts) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            parse(body)

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_status, status, body}}

          {:error, reason} ->
            {:error, {:transport, reason}}
        end
    end
  end

  defp headers(key) do
    cfg = config()

    [
      {"authorization", "Bearer #{key}"},
      {"content-type", "application/json"}
    ]
    |> maybe_header("http-referer", cfg[:referer])
    |> maybe_header("x-title", cfg[:title])
  end

  defp maybe_header(headers, _name, value) when value in [nil, ""], do: headers
  defp maybe_header(headers, name, value), do: [{name, value} | headers]

  # OpenAI format carries the system prompt as a leading `system` message.
  defp build_body(%Request{} = r) do
    messages =
      case r.system do
        nil -> r.messages
        "" -> r.messages
        system -> [%{role: "system", content: system} | r.messages]
      end

    %{
      "model" => r.model,
      "max_tokens" => r.max_tokens,
      "temperature" => r.temperature,
      "messages" => Enum.map(messages, &%{"role" => &1.role, "content" => &1.content})
    }
  end

  defp parse(%{"choices" => [%{"message" => %{"content" => content}} = choice | _]} = body) do
    {:ok,
     %Response{
       text: content || "",
       model: body["model"],
       finish_reason: choice["finish_reason"],
       usage: usage(body["usage"]),
       raw: body
     }}
  end

  defp parse(body), do: {:error, {:unexpected_response, body}}

  defp usage(%{"prompt_tokens" => input, "completion_tokens" => output}) do
    %{input_tokens: input, output_tokens: output}
  end

  defp usage(_), do: nil

  defp api_key do
    config()[:api_key] || System.get_env("OPENROUTER_API_KEY")
  end

  defp api_url, do: config()[:api_url] || @default_url

  defp config, do: Application.get_env(:hermes, :llm, [])[:openrouter] || []
end
