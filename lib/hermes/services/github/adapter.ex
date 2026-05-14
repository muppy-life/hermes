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

  @doc """
  Returns the GraphQL node ID of an issue (needed before adding to a project).
  """
  @callback get_issue_node_id(String.t(), String.t(), pos_integer()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Adds an issue (by node ID) to a Projects v2 board. Returns the project
  item ID, which is later passed to `move_item/4`.
  """
  @callback add_issue_to_project(String.t(), String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Moves a project item to a different status column.
  """
  @callback move_item(
              project_id :: String.t(),
              item_id :: String.t(),
              field_id :: String.t(),
              option_id :: String.t()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  Lists status field options for a project. Used to seed the mapping table.

  Returns `[%{id, name}]`.
  """
  @callback list_status_options(project_id :: String.t(), field_id :: String.t()) ::
              {:ok, [%{id: String.t(), name: String.t()}]} | {:error, term()}
end
