defmodule HermesWeb.DevLive.GithubInbox do
  @moduledoc """
  Dev-only inspector for the in-memory GitHub adapter.

  Lists the fake issues created by `Hermes.Services.GitHub.InMemory`,
  shows their state and comments, and lets developers toggle the state
  to simulate a GitHub-side change (useful for testing reverse sync).
  """

  use HermesWeb, :live_view

  alias Hermes.Services.GitHub
  alias Hermes.Services.GitHub.InMemory

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dev — GitHub fake")
     |> assign(:adapter, GitHub.adapter())
     |> load_issues()}
  end

  @impl true
  def handle_event("toggle_state", %{"owner" => o, "repo" => r, "number" => n}, socket) do
    issue = InMemory.get(o, r, String.to_integer(n))
    new_state = if issue && issue.state == "open", do: "closed", else: "open"
    InMemory.set_state(o, r, String.to_integer(n), new_state)
    {:noreply, load_issues(socket)}
  end

  def handle_event("reset", _params, socket) do
    InMemory.reset()
    {:noreply, load_issues(socket)}
  end

  defp load_issues(socket) do
    if socket.assigns.adapter == InMemory do
      issues =
        Enum.map(InMemory.list_issues(), fn issue ->
          Map.put(issue, :comments, InMemory.comments_for(issue.owner, issue.repo, issue.number))
        end)

      assign(socket, :issues, issues)
    else
      assign(socket, :issues, [])
    end
  end
end
