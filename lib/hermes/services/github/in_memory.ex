defmodule Hermes.Services.GitHub.InMemory do
  @moduledoc """
  In-memory GitHub adapter for dev. Backed by an `Agent` that stores
  fake issues keyed by `{owner, repo, number}`.

  Inspect or mutate state via:

    * `list_issues/0`
    * `get/3`
    * `set_state/4`
    * `add_comment/4`
    * `reset/0`

  These helpers power the `/dev/github` LiveView and tests.
  """

  @behaviour Hermes.Services.GitHub.Adapter

  use Agent

  @doc """
  Starts the in-memory store. Mounted by the application supervisor only
  when the InMemory adapter is configured.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(&initial_state/0, name: __MODULE__)
  end

  defp initial_state do
    %{
      issues: %{},
      counter: %{},
      comments: %{},
      # project_id => [%{id, name}]
      status_options: default_status_options(),
      # item_id => %{project_id, content_node_id, status_option_id}
      project_items: %{},
      # auto-increment for synthetic item ids
      item_counter: 0
    }
  end

  defp default_status_options do
    %{
      "PVT_DEV" => [
        %{id: "OPT_NEW", name: "New"},
        %{id: "OPT_NEED", name: "Need requirement"},
        %{id: "OPT_PENDING", name: "Pending"},
        %{id: "OPT_PROGRESS", name: "In progress"},
        %{id: "OPT_REVIEW", name: "Review"},
        %{id: "OPT_DONE", name: "Done"},
        %{id: "OPT_BLOCKED", name: "Blocked"}
      ]
    }
  end

  @impl true
  def create_issue(%{owner: owner, repo: repo, title: title, body: body, labels: labels}) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {owner, repo}
      number = (state.counter[key] || 0) + 1

      issue = %{
        owner: owner,
        repo: repo,
        number: number,
        title: title,
        body: body,
        labels: labels,
        state: "open",
        url: "https://github.example/#{owner}/#{repo}/issues/#{number}",
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      new_state = %{
        state
        | issues: Map.put(state.issues, {owner, repo, number}, issue),
          counter: Map.put(state.counter, key, number)
      }

      {{:ok, %{number: number, url: issue.url}}, new_state}
    end)
  end

  @impl true
  def update_issue(%{
        owner: owner,
        repo: repo,
        number: number,
        title: title,
        body: body,
        labels: labels
      }) do
    mutate(owner, repo, number, fn issue ->
      %{issue | title: title, body: body, labels: labels, updated_at: DateTime.utc_now()}
    end)
  end

  @impl true
  def set_issue_state(%{owner: owner, repo: repo, number: number}, state)
      when state in [:open, :closed] do
    mutate(owner, repo, number, fn issue ->
      %{issue | state: Atom.to_string(state), updated_at: DateTime.utc_now()}
    end)
  end

  @impl true
  def create_comment(%{owner: owner, repo: repo, number: number}, body) when is_binary(body) do
    key = {owner, repo, number}

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.issues, key) do
        nil ->
          {{:error, {:http_error, 404, %{"message" => "Not Found"}}}, state}

        _issue ->
          comment = %{body: body, inserted_at: DateTime.utc_now()}
          comments = Map.update(state.comments, key, [comment], &(&1 ++ [comment]))
          {{:ok, comment}, %{state | comments: comments}}
      end
    end)
  end

  @impl true
  def get_issue(owner, repo, number) when is_integer(number) do
    case Agent.get(__MODULE__, &Map.get(&1.issues, {owner, repo, number})) do
      nil -> {:error, {:http_error, 404, %{"message" => "Not Found"}}}
      issue -> {:ok, %{number: issue.number, url: issue.url, state: issue.state}}
    end
  end

  @impl true
  def get_issue_node_id(owner, repo, number) when is_integer(number) do
    case Agent.get(__MODULE__, &Map.get(&1.issues, {owner, repo, number})) do
      nil -> {:error, {:http_error, 404, %{"message" => "Not Found"}}}
      _issue -> {:ok, "ISSUE_NODE_#{owner}_#{repo}_#{number}"}
    end
  end

  @impl true
  def add_issue_to_project(project_id, content_node_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      next = state.item_counter + 1
      item_id = "PVTI_#{next}"

      item = %{
        id: item_id,
        project_id: project_id,
        content_node_id: content_node_id,
        status_option_id: nil
      }

      {{:ok, item_id},
       %{
         state
         | item_counter: next,
           project_items: Map.put(state.project_items, item_id, item)
       }}
    end)
  end

  @impl true
  def move_item(project_id, item_id, _field_id, option_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.project_items, item_id) do
        nil ->
          {{:error, {:http_error, 404, %{"message" => "Item not found"}}}, state}

        item ->
          updated = %{item | status_option_id: option_id, project_id: project_id}

          {{:ok, %{"id" => item_id}},
           %{state | project_items: Map.put(state.project_items, item_id, updated)}}
      end
    end)
  end

  @impl true
  def list_status_options(project_id, _field_id) do
    options =
      Agent.get(__MODULE__, fn state ->
        # Return whatever project_id has, defaulting to the seeded dev set.
        state.status_options[project_id] || state.status_options["PVT_DEV"] || []
      end)

    {:ok, options}
  end

  # Dev/test helpers

  @doc "Returns all fake issues, newest first."
  def list_issues do
    Agent.get(__MODULE__, fn state ->
      state.issues
      |> Map.values()
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    end)
  end

  @doc "Returns a single fake issue or nil."
  def get(owner, repo, number) do
    Agent.get(__MODULE__, &Map.get(&1.issues, {owner, repo, number}))
  end

  @doc "Returns comments for an issue, oldest first."
  def comments_for(owner, repo, number) do
    Agent.get(__MODULE__, &Map.get(&1.comments, {owner, repo, number}, []))
  end

  @doc """
  Forces an issue into a state. Use to simulate someone closing the issue
  on GitHub for reverse-sync testing.
  """
  def set_state(owner, repo, number, state) when state in ["open", "closed"] do
    mutate(owner, repo, number, fn issue ->
      %{issue | state: state, updated_at: DateTime.utc_now()}
    end)
  end

  @doc "Clears all fake state. Used by tests."
  def reset do
    Agent.update(__MODULE__, fn _ -> initial_state() end)
  end

  @doc "Lists project items along with their resolved issue ref + status."
  def list_project_items do
    Agent.get(__MODULE__, fn state ->
      Enum.map(state.project_items, fn {_id, item} -> item end)
    end)
  end

  @doc """
  Finds the project_item_id for a given issue node id (synthetic in dev).
  """
  def project_item_for_issue(content_node_id) do
    Agent.get(__MODULE__, fn state ->
      Enum.find_value(state.project_items, fn {_id, item} ->
        if item.content_node_id == content_node_id, do: item, else: nil
      end)
    end)
  end

  defp mutate(owner, repo, number, fun) do
    key = {owner, repo, number}

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.issues, key) do
        nil ->
          {{:error, {:http_error, 404, %{"message" => "Not Found"}}}, state}

        issue ->
          updated = fun.(issue)
          {{:ok, updated}, %{state | issues: Map.put(state.issues, key, updated)}}
      end
    end)
  end
end
