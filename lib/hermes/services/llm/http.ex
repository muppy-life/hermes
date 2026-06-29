defmodule Hermes.Services.LLM.HTTP do
  @moduledoc """
  Shared HTTP helpers for the HTTP-backed LLM adapters.

  Tests can inject a Req plug (or any Req option) via `:llm_req_options` to stub
  responses without real network calls — mirroring the GitHub adapter's
  `:github_req_options` hook.

      Application.put_env(:hermes, :llm_req_options,
        plug: fn conn -> Req.Test.json(conn, %{...}) end
      )
  """

  @doc """
  Merges any configured `:llm_req_options` into a Req options keyword list.
  """
  @spec maybe_put_test_options(keyword()) :: keyword()
  def maybe_put_test_options(opts) do
    case Application.get_env(:hermes, :llm_req_options) do
      extra when is_list(extra) -> Keyword.merge(opts, extra)
      _ -> opts
    end
  end
end
