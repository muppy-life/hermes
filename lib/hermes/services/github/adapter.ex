defmodule Hermes.Services.GitHub.Adapter do
  @moduledoc """
  Behaviour for GitHub backends.

  Implemented by `Hermes.Services.GitHub.HTTP` (real GitHub REST API) and
  `Hermes.Services.GitHub.InMemory` (dev fake). The `Hermes.Services.GitHub`
  facade renders request payloads and dispatches here.
  """

  @type target :: %{owner: String.t(), repo: String.t()}
  @type issue_ref :: %{owner: String.t(), repo: String.t(), number: pos_integer()}
  @type create_payload :: %{
          owner: String.t(),
          repo: String.t(),
          title: String.t(),
          body: String.t(),
          labels: [String.t()]
        }
  @type update_payload :: %{
          owner: String.t(),
          repo: String.t(),
          number: pos_integer(),
          title: String.t(),
          body: String.t(),
          labels: [String.t()]
        }

  @callback create_issue(create_payload) ::
              {:ok, %{number: pos_integer(), url: String.t()}} | {:error, term()}

  @callback update_issue(update_payload) :: {:ok, map()} | {:error, term()}

  @callback set_issue_state(issue_ref, :open | :closed) :: {:ok, map()} | {:error, term()}

  @callback create_comment(issue_ref, String.t()) :: {:ok, map()} | {:error, term()}

  @callback get_issue(String.t(), String.t(), pos_integer()) ::
              {:ok, %{number: pos_integer(), url: String.t(), state: String.t()}}
              | {:error, term()}
end
