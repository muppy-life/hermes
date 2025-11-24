defmodule Hermes.Services.Claude do
  @moduledoc """
  Service module for interacting with the Claude API.
  """

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  @doc """
  Sends a message to the Claude API and returns the response.

  ## Parameters
    - messages: List of message maps with "role" and "content" keys
    - opts: Keyword list of options
      - :model - The Claude model to use (default: "claude-sonnet-4-20250514")
      - :max_tokens - Maximum tokens in response (default: 1024)
      - :temperature - Temperature for response randomness (default: 1.0)
      - :system - System prompt (optional)

  ## Examples

      iex> Hermes.Services.Claude.send_message([
      ...>   %{"role" => "user", "content" => "Hello!"}
      ...> ])
      {:ok, %{
        "content" => [%{"text" => "Hello! How can I help you?", "type" => "text"}],
        "role" => "assistant",
        ...
      }}

  """
  def send_message(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    max_tokens = Keyword.get(opts, :max_tokens, 1024)
    temperature = Keyword.get(opts, :temperature, 1.0)
    system = Keyword.get(opts, :system)

    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, "ANTHROPIC_API_KEY not configured"}
    else
      body = build_request_body(messages, model, max_tokens, temperature, system)

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]

      case Req.post(@api_url, json: body, headers: headers) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %Req.Response{status: status, body: error_body}} ->
          {:error, "API request failed with status #{status}: #{inspect(error_body)}"}

        {:error, error} ->
          {:error, "HTTP request failed: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Sends a simple text message to Claude and returns just the text response.

  ## Examples

      iex> Hermes.Services.Claude.ask("What is 2+2?")
      {:ok, "2+2 equals 4."}

  """
  def ask(prompt, opts \\ []) do
    messages = [%{"role" => "user", "content" => prompt}]

    case send_message(messages, opts) do
      {:ok, response} ->
        text = extract_text_from_response(response)
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a message with conversation history to Claude.

  ## Parameters
    - conversation: List of message maps with :role and :content keys
    - opts: Options (same as send_message/2)

  ## Examples

      iex> conversation = [
      ...>   %{role: "user", content: "My name is Alice"},
      ...>   %{role: "assistant", content: "Nice to meet you, Alice!"},
      ...>   %{role: "user", content: "What's my name?"}
      ...> ]
      iex> Hermes.Services.Claude.chat(conversation)
      {:ok, "Your name is Alice."}

  """
  def chat(conversation, opts \\ []) do
    # Convert atom keys to string keys for API compatibility
    messages =
      Enum.map(conversation, fn msg ->
        %{
          "role" => to_string(msg[:role] || msg["role"]),
          "content" => msg[:content] || msg["content"]
        }
      end)

    case send_message(messages, opts) do
      {:ok, response} ->
        text = extract_text_from_response(response)
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp get_api_key do
    Application.get_env(:hermes, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end

  defp build_request_body(messages, model, max_tokens, temperature, system) do
    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "temperature" => temperature,
      "messages" => messages
    }

    if system do
      Map.put(body, "system", system)
    else
      body
    end
  end

  defp extract_text_from_response(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(fn block -> block["type"] == "text" end)
    |> Enum.map_join("\n", fn block -> block["text"] end)
  end

  defp extract_text_from_response(_), do: ""
end
