defmodule Hermes.Services.LLM.Request do
  @moduledoc """
  Provider-agnostic LLM completion request.

  The `Hermes.Services.LLM` facade builds one of these and hands it to the
  configured adapter (`Anthropic`, `OpenRouter`, `InMemory`). Adapters translate
  it into their wire format — they never see the caller's loose keyword opts.

  Fields:
    * `:messages`    — list of `%{role: String.t(), content: String.t()}`
    * `:model`       — provider model id (adapter-specific string)
    * `:max_tokens`  — cap on tokens in the response
    * `:temperature` — sampling temperature
    * `:system`      — optional system prompt
  """

  @enforce_keys [:messages, :model]
  defstruct messages: [],
            model: nil,
            max_tokens: 1024,
            temperature: 1.0,
            system: nil

  @type message :: %{role: String.t(), content: String.t()}

  @type t :: %__MODULE__{
          messages: [message()],
          model: String.t(),
          max_tokens: pos_integer(),
          temperature: float(),
          system: String.t() | nil
        }
end
