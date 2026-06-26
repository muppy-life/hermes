# LLM Service

Provider-agnostic LLM integration. The `Hermes.Services.LLM` facade builds a
normalised request and dispatches to a configured adapter, so app code never
hardcodes a provider.

## Adapters

| Adapter                            | Backend                                            |
| ---------------------------------- | -------------------------------------------------- |
| `Hermes.Services.LLM.Anthropic`    | Anthropic Messages API (`/v1/messages`)            |
| `Hermes.Services.LLM.OpenRouter`   | OpenRouter, OpenAI-compatible chat completions     |
| `Hermes.Services.LLM.InMemory`     | Deterministic fake — no network (dev/test default) |

## Selecting a provider

Defaults live in `config/config.exs`; runtime keys/selection in
`config/runtime.exs`. The provider can be switched with a single env var:

```bash
export LLM_PROVIDER=openrouter            # or "anthropic"
export OPENROUTER_API_KEY="sk-or-..."     # provider-specific key
export ANTHROPIC_API_KEY="sk-ant-..."
export LLM_DEFAULT_MODEL="anthropic/claude-sonnet-4"   # optional override
```

OpenRouter keys reach every model it fronts; pick the model with a namespaced
id like `"anthropic/claude-sonnet-4"` or `"openai/gpt-4o"`.

- **dev** uses `InMemory` by default (works offline); set `LLM_PROVIDER` to opt
  into a real provider.
- **test** uses `InMemory` always.

## Usage

```elixir
# Single prompt -> text
{:ok, text} = Hermes.Services.LLM.ask("What is 2+2?")

# Conversation history -> text
{:ok, text} =
  Hermes.Services.LLM.chat([
    %{role: "user", content: "My name is Alice"},
    %{role: "assistant", content: "Nice to meet you, Alice!"},
    %{role: "user", content: "What's my name?"}
  ])

# Full control -> %Hermes.Services.LLM.Response{}
{:ok, resp} =
  Hermes.Services.LLM.complete("Write a haiku about coding",
    model: "claude-sonnet-4-20250514",
    max_tokens: 200,
    temperature: 0.7,
    system: "You are a poetic coding assistant."
  )

resp.text          # assistant text
resp.usage         # %{input_tokens: _, output_tokens: _}
resp.finish_reason # "end_turn" / "stop" / ...
resp.raw           # untouched decoded provider body
```

### Options

- `:model` — model id (defaults to configured `:default_model`)
- `:max_tokens` — response token cap (default 1024)
- `:temperature` — sampling temperature (default 1.0)
- `:system` — system prompt (optional)

## Error contract

Errors are tagged so callers branch on cause, not on a string:

- `{:error, :missing_api_key}`
- `{:error, {:http_status, status, body}}`
- `{:error, {:transport, reason}}`
- `{:error, {:unexpected_response, body}}`

## Testing

The HTTP adapters honour a `:llm_req_options` config hook for injecting a Req
test plug (no real network):

```elixir
Application.put_env(:hermes, :llm_req_options,
  plug: fn conn -> Req.Test.json(conn, %{...}) end
)
```

Or stub the `InMemory` adapter's output:

```elixir
config :hermes, :llm_stub_response, "flowchart TD\n  A --> B"
# or a request-aware function:
config :hermes, :llm_stub_response, fn req -> "echo: " <> List.last(req.messages).content end
```

## Deprecated

`Hermes.Services.Claude` remains as a thin backward-compatible shim over the
facade. New code should call `Hermes.Services.LLM` directly.
