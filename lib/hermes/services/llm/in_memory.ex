defmodule Hermes.Services.LLM.InMemory do
  @moduledoc """
  Deterministic, network-free LLM adapter for dev and test.

  Returns a canned `Response` so features that depend on an LLM (e.g. diagram
  generation) work offline without an API key. Override the text per-test or
  per-environment:

      # Static text:
      config :hermes, :llm_stub_response, "flowchart TD\\n  A --> B"

      # Or a function for request-aware stubbing:
      config :hermes, :llm_stub_response, fn %Request{} = req ->
        "echo: " <> List.last(req.messages).content
      end
  """

  @behaviour Hermes.Services.LLM.Adapter

  alias Hermes.Services.LLM.{Request, Response}

  @default_text """
  flowchart TD
    A[Current situation] --> B[Solution step]
    B --> C[Expected output]
  """

  @impl true
  def complete(%Request{} = request) do
    text = resolve_text(request)

    {:ok,
     %Response{
       text: text,
       model: request.model,
       finish_reason: "stop",
       usage: %{input_tokens: 0, output_tokens: 0},
       raw: %{"adapter" => "in_memory"}
     }}
  end

  defp resolve_text(%Request{} = request) do
    case Application.get_env(:hermes, :llm_stub_response) do
      nil -> String.trim(@default_text)
      fun when is_function(fun, 1) -> fun.(request)
      text when is_binary(text) -> text
    end
  end
end
