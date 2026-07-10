defmodule Hermes.Services.LLM.Adapter do
  @moduledoc """
  Behaviour for LLM backends.

  Implemented by:

    * `Hermes.Services.LLM.Anthropic`  — Anthropic Messages API
    * `Hermes.Services.LLM.OpenRouter` — OpenRouter (OpenAI-compatible) API
    * `Hermes.Services.LLM.InMemory`   — deterministic fake for dev/test

  The `Hermes.Services.LLM` facade builds a `Request` and dispatches to the
  configured adapter, which returns a normalised `Response`.

  ## Error contract

  Adapters return a tagged error so callers branch on cause, not on a string:

    * `{:error, :missing_api_key}`          — no key configured
    * `{:error, {:http_status, status, body}}` — non-2xx HTTP response
    * `{:error, {:transport, reason}}`      — network/HTTP client failure
    * `{:error, {:unexpected_response, body}}` — 2xx but unparseable shape
  """

  alias Hermes.Services.LLM.{Request, Response}

  @type error ::
          :missing_api_key
          | {:http_status, integer(), term()}
          | {:transport, term()}
          | {:unexpected_response, term()}

  @callback complete(Request.t()) :: {:ok, Response.t()} | {:error, error()}
end
