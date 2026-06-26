defmodule Hermes.Services.LLM do
  @moduledoc """
  Provider-agnostic facade for LLM completions.

  Builds a normalised `Request` and dispatches to the configured adapter:

    * `Hermes.Services.LLM.Anthropic`  — Anthropic Messages API
    * `Hermes.Services.LLM.OpenRouter` — OpenRouter (OpenAI-compatible) API
    * `Hermes.Services.LLM.InMemory`   — deterministic fake (dev/test)

  Select the adapter and default model via config:

      config :hermes, :llm,
        adapter: Hermes.Services.LLM.OpenRouter,
        default_model: "anthropic/claude-sonnet-4"

  ## Entry points

    * `complete/2` — full control, returns a `Response` struct
    * `ask/2`      — single prompt in, text out
    * `chat/2`     — conversation history in, text out

  All three accept the same options:

    * `:model`       — model id (defaults to configured `:default_model`)
    * `:max_tokens`  — response token cap (default 1024)
    * `:temperature` — sampling temperature (default 1.0)
    * `:system`      — system prompt (optional)
  """

  alias Hermes.Services.LLM.{Request, Response}

  require Logger

  @default_adapter Hermes.Services.LLM.Anthropic
  @default_model "claude-sonnet-4-20250514"

  @doc """
  Runs a completion and returns the normalised `Response`.

  `input` is either a list of message maps (`%{role: ..., content: ...}`, string
  or atom keys) or a single prompt string.
  """
  @spec complete([map()] | String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def complete(input, opts \\ []) do
    request = build_request(input, opts)

    Logger.info(
      "LLM.complete adapter=#{inspect(adapter())} model=#{request.model} messages=#{length(request.messages)}"
    )

    case adapter().complete(request) do
      {:ok, %Response{} = response} = ok ->
        Logger.info(
          "LLM.complete ok model=#{response.model || request.model} finish=#{response.finish_reason} usage=#{inspect(response.usage)}"
        )

        ok

      {:error, reason} = err ->
        Logger.warning("LLM.complete failed model=#{request.model} reason=#{inspect(reason)}")
        err
    end
  end

  @doc """
  Sends a single prompt and returns just the response text.

      iex> Hermes.Services.LLM.ask("What is 2+2?")
      {:ok, "2+2 equals 4."}
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(prompt, opts \\ []) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
    |> complete(opts)
    |> to_text()
  end

  @doc """
  Sends a conversation (list of message maps) and returns just the response text.

      iex> Hermes.Services.LLM.chat([
      ...>   %{role: "user", content: "My name is Alice"},
      ...>   %{role: "assistant", content: "Nice to meet you, Alice!"},
      ...>   %{role: "user", content: "What's my name?"}
      ...> ])
      {:ok, "Your name is Alice."}
  """
  @spec chat([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(conversation, opts \\ []) when is_list(conversation) do
    conversation
    |> complete(opts)
    |> to_text()
  end

  @doc "Returns the configured adapter module. Defaults to the Anthropic adapter."
  def adapter do
    config()[:adapter] || @default_adapter
  end

  @doc "Returns the configured default model for the active adapter."
  def default_model do
    config()[:default_model] || @default_model
  end

  defp build_request(input, opts) when is_binary(input) do
    build_request([%{role: "user", content: input}], opts)
  end

  defp build_request(messages, opts) when is_list(messages) do
    %Request{
      messages: Enum.map(messages, &normalize_message/1),
      model: Keyword.get(opts, :model, default_model()),
      max_tokens: Keyword.get(opts, :max_tokens, 1024),
      temperature: Keyword.get(opts, :temperature, 1.0),
      system: Keyword.get(opts, :system)
    }
  end

  # Accept atom- or string-keyed message maps and normalise to string roles.
  defp normalize_message(msg) do
    %{
      role: to_string(msg[:role] || msg["role"]),
      content: msg[:content] || msg["content"]
    }
  end

  defp to_text({:ok, %Response{text: text}}), do: {:ok, text}
  defp to_text({:error, _} = err), do: err

  defp config, do: Application.get_env(:hermes, :llm, [])
end
