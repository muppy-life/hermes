# Claude API Service

This service provides integration with Anthropic's Claude API for sending messages and getting responses.

## Setup

1. Get an API key from [Anthropic Console](https://console.anthropic.com/)
2. Set the environment variable:

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

Or add it to your `.env` file (make sure it's in `.gitignore`):

```
ANTHROPIC_API_KEY=your-api-key-here
```

## Usage

### Simple Question

```elixir
# Ask a simple question
{:ok, response} = Hermes.Services.Claude.ask("What is 2+2?")
IO.puts(response)
# => "2+2 equals 4."
```

### Conversation with History

```elixir
# Have a conversation with context
conversation = [
  %{role: "user", content: "My name is Alice"},
  %{role: "assistant", content: "Nice to meet you, Alice!"},
  %{role: "user", content: "What's my name?"}
]

{:ok, response} = Hermes.Services.Claude.chat(conversation)
IO.puts(response)
# => "Your name is Alice."
```

### Advanced Usage with Options

```elixir
# Use a specific model and system prompt
{:ok, response} = Hermes.Services.Claude.ask(
  "Write a haiku about coding",
  model: "claude-3-5-sonnet-20241022",
  max_tokens: 200,
  temperature: 0.7,
  system: "You are a poetic coding assistant."
)
```

### Raw API Access

```elixir
# Use the raw API for full control
messages = [
  %{"role" => "user", "content" => "Hello!"}
]

{:ok, response} = Hermes.Services.Claude.send_message(messages, [
  model: "claude-sonnet-4-20250514",
  max_tokens: 1024
])

# Response structure:
# %{
#   "id" => "msg_...",
#   "type" => "message",
#   "role" => "assistant",
#   "content" => [%{"type" => "text", "text" => "Hello! How can I help you?"}],
#   "model" => "claude-sonnet-4-20250514",
#   ...
# }
```

## Available Models

- `claude-sonnet-4-20250514` (default) - Most intelligent model
- `claude-3-5-sonnet-20241022` - Fast and intelligent
- `claude-3-5-haiku-20241022` - Fastest responses
- `claude-opus-4-20250514` - Most capable model

## Options

- `:model` - The Claude model to use (default: "claude-sonnet-4-20250514")
- `:max_tokens` - Maximum tokens in response (default: 1024)
- `:temperature` - Temperature for response randomness 0.0-1.0 (default: 1.0)
- `:system` - System prompt to set context (optional)

## Error Handling

```elixir
case Hermes.Services.Claude.ask("Hello") do
  {:ok, response} ->
    IO.puts("Success: #{response}")

  {:error, reason} ->
    IO.puts("Error: #{reason}")
end
```

## Testing in IEx

```bash
iex -S mix
```

```elixir
# Simple test
Hermes.Services.Claude.ask("Say hello!")

# With conversation
conversation = [
  %{role: "user", content: "I like pizza"},
  %{role: "assistant", content: "Pizza is delicious!"},
  %{role: "user", content: "What do I like?"}
]
Hermes.Services.Claude.chat(conversation)
```

## Notes

- The API key is loaded from the `ANTHROPIC_API_KEY` environment variable
- If the API key is not set, all requests will return `{:error, "ANTHROPIC_API_KEY not configured"}`
- The service uses the Req HTTP client library
- Rate limits and pricing depend on your Anthropic API plan
