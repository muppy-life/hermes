defmodule Hermes.Services.LLMTest do
  use ExUnit.Case, async: false

  alias Hermes.Services.LLM
  alias Hermes.Services.LLM.Response

  # Each test pins its own adapter; restore afterwards so the suite default
  # (InMemory, from config/test.exs) is left intact.
  setup do
    original = Application.get_env(:hermes, :llm)
    on_exit(fn -> Application.put_env(:hermes, :llm, original) end)
    :ok
  end

  defp put_llm(opts) do
    base = Application.get_env(:hermes, :llm, [])
    Application.put_env(:hermes, :llm, Keyword.merge(base, opts))
  end

  describe "InMemory adapter (suite default)" do
    test "ask/2 returns canned text without network" do
      assert {:ok, text} = LLM.ask("draw me a diagram")
      assert is_binary(text)
      assert text =~ "flowchart"
    end

    test "stub response can be overridden with a string" do
      Application.put_env(:hermes, :llm_stub_response, "hello world")
      on_exit(fn -> Application.delete_env(:hermes, :llm_stub_response) end)

      assert {:ok, "hello world"} = LLM.ask("anything")
    end

    test "stub response can be a request-aware function" do
      Application.put_env(:hermes, :llm_stub_response, fn req ->
        "echo:" <> List.last(req.messages).content
      end)

      on_exit(fn -> Application.delete_env(:hermes, :llm_stub_response) end)

      assert {:ok, "echo:ping"} = LLM.ask("ping")
    end

    test "complete/2 returns a normalised Response struct" do
      assert {:ok, %Response{finish_reason: "stop", usage: %{input_tokens: 0}}} =
               LLM.complete("hi")
    end
  end

  describe "Anthropic adapter" do
    test "normalises a Messages API response via Req test plug" do
      put_llm(adapter: Hermes.Services.LLM.Anthropic, anthropic: [api_key: "test-key"])

      Application.put_env(:hermes, :llm_req_options,
        plug: fn conn ->
          Req.Test.json(conn, %{
            "model" => "claude-sonnet-4-20250514",
            "stop_reason" => "end_turn",
            "content" => [%{"type" => "text", "text" => "4"}],
            "usage" => %{"input_tokens" => 10, "output_tokens" => 1}
          })
        end
      )

      on_exit(fn -> Application.delete_env(:hermes, :llm_req_options) end)

      assert {:ok, %Response{} = resp} = LLM.complete("2+2?")
      assert resp.text == "4"
      assert resp.finish_reason == "end_turn"
      assert resp.usage == %{input_tokens: 10, output_tokens: 1}
    end

    test "returns :missing_api_key when no key configured" do
      put_llm(adapter: Hermes.Services.LLM.Anthropic, anthropic: [api_key: nil])

      # Guard against a real key leaking in from the environment, but restore it
      # afterwards so later tests/modules still see the developer's shell value.
      original_key = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      on_exit(fn -> if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key) end)

      assert {:error, :missing_api_key} = LLM.ask("hi")
    end
  end

  describe "OpenRouter adapter" do
    test "normalises an OpenAI-compatible response via Req test plug" do
      put_llm(adapter: Hermes.Services.LLM.OpenRouter, openrouter: [api_key: "test-key"])

      Application.put_env(:hermes, :llm_req_options,
        plug: fn conn ->
          Req.Test.json(conn, %{
            "model" => "anthropic/claude-sonnet-4",
            "choices" => [
              %{"finish_reason" => "stop", "message" => %{"content" => "pong"}}
            ],
            "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 1}
          })
        end
      )

      on_exit(fn -> Application.delete_env(:hermes, :llm_req_options) end)

      assert {:ok, %Response{} = resp} = LLM.complete("ping")
      assert resp.text == "pong"
      assert resp.finish_reason == "stop"
      assert resp.usage == %{input_tokens: 5, output_tokens: 1}
    end

    test "sends the system prompt as a leading system message" do
      put_llm(adapter: Hermes.Services.LLM.OpenRouter, openrouter: [api_key: "test-key"])

      Application.put_env(:hermes, :llm_req_options,
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          send(self(), {:request_body, decoded})

          Req.Test.json(conn, %{
            "choices" => [%{"message" => %{"content" => "ok"}}]
          })
        end
      )

      on_exit(fn -> Application.delete_env(:hermes, :llm_req_options) end)

      assert {:ok, _} = LLM.ask("hello", system: "be terse")
      assert_received {:request_body, %{"messages" => messages}}
      assert [%{"role" => "system", "content" => "be terse"} | _] = messages
    end
  end
end
