defmodule HermesWeb.DevLive.GithubInbox do
  @moduledoc """
  Dev-only inspector for the in-memory GitHub adapter.

  Lists the fake issues created by `Hermes.Services.GitHub.InMemory`,
  shows their state, comments, and project board column. The "Move to..."
  buttons simulate a GitHub project board column change by invoking the
  reverse-sync handler directly (no HTTP/signature round trip).
  """

  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Services.GitHub
  alias Hermes.Services.GitHub.InMemory

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dev — GitHub fake")
     |> assign(:adapter, GitHub.adapter())
     |> load()}
  end

  @impl true
  def handle_event("toggle_state", %{"owner" => o, "repo" => r, "number" => n}, socket) do
    number = String.to_integer(n)
    issue = InMemory.get(o, r, number)
    new_state = if issue && issue.state == "open", do: "closed", else: "open"

    InMemory.set_state(o, r, number, new_state)

    # Simulate the GitHub `issues` webhook so reverse-sync runs end-to-end.
    Requests.handle_issue_event(%{
      "owner" => o,
      "repo" => r,
      "number" => number,
      "state" => new_state
    })

    {:noreply, load(socket)}
  end

  def handle_event(
        "move_card",
        %{"item_id" => item_id, "option_id" => option_id, "option_name" => option_name},
        socket
      ) do
    # Simulate the webhook payload structure for a projects_v2_item edited
    # event where the Status field moved between options.
    payload = %{
      "id" => item_id,
      "changes" => %{
        "field_value" => %{
          "to" => %{"id" => option_id, "name" => option_name}
        }
      }
    }

    # Update the InMemory state so the dev page reflects the move too.
    InMemory.move_item("PVT_DEV", item_id, "FIELD_STATUS", option_id)
    Requests.handle_project_item_event(payload)

    {:noreply, load(socket)}
  end

  def handle_event("reset", _params, socket) do
    InMemory.reset()
    {:noreply, load(socket)}
  end

  defp load(socket) do
    if socket.assigns.adapter == InMemory do
      issues =
        Enum.map(InMemory.list_issues(), fn issue ->
          Map.put(issue, :comments, InMemory.comments_for(issue.owner, issue.repo, issue.number))
        end)

      items = InMemory.list_project_items()
      {:ok, options} = InMemory.list_status_options("PVT_DEV", "FIELD_STATUS")

      socket
      |> assign(:issues, issues)
      |> assign(:items, items)
      |> assign(:options, options)
    else
      socket
      |> assign(:issues, [])
      |> assign(:items, [])
      |> assign(:options, [])
    end
  end
end
