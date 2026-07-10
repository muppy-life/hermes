defmodule Hermes.Services.LLM.Response do
  @moduledoc """
  Provider-agnostic LLM completion response.

  Adapters normalise each provider's payload into this struct so callers never
  branch on wire shape. `:raw` keeps the untouched decoded body for debugging or
  provider-specific needs.

  Fields:
    * `:text`          — concatenated assistant text
    * `:model`         — model that produced the response (as reported by the API)
    * `:usage`         — `%{input_tokens, output_tokens}` (nil when not reported)
    * `:finish_reason` — why generation stopped (e.g. "stop", "length", "end_turn")
    * `:raw`           — the decoded provider response body
  """

  defstruct text: "",
            model: nil,
            usage: nil,
            finish_reason: nil,
            raw: nil

  @type usage :: %{input_tokens: non_neg_integer() | nil, output_tokens: non_neg_integer() | nil}

  @type t :: %__MODULE__{
          text: String.t(),
          model: String.t() | nil,
          usage: usage() | nil,
          finish_reason: String.t() | nil,
          raw: map() | nil
        }
end
