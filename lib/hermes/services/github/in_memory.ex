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

  defp initial_state, do: %{issues: %{}, counter: %{}, comments: %{}}

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
