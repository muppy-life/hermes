defmodule Hermes.Requests.GitHubCreateStatusTest do
  use Hermes.DataCase, async: false

  alias Hermes.Accounts
  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.GitHubStatusMapping
  alias Hermes.Services.GitHub.InMemory

  setup do
    original_adapter = Application.get_env(:hermes, :github_adapter)
    original_github = Application.get_env(:hermes, :github)

    # Disable integration during fixture setup so the create-request hook
    # does not touch GitHub. Tests re-enable explicitly.
    Application.put_env(:hermes, :github, token: nil, owner: nil)

    if pid = Process.whereis(InMemory) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end

    start_supervised!(InMemory)

    on_exit(fn ->
      restore_env(:github_adapter, original_adapter)
      restore_env(:github, original_github)
    end)

    for {status, option_id, name} <- [
          {"new", "OPT_NEW", "New"},
          {"in_progress", "OPT_PROGRESS", "In progress"}
        ] do
      %GitHubStatusMapping{}
      |> GitHubStatusMapping.changeset(%{
        hermes_status: status,
        github_option_id: option_id,
        github_option_name: name
      })
      |> Repo.insert!()
    end

    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "u@test.com",
        hashed_password: "h",
        role: "team_member",
        team_id: team.id
      })

    {:ok, request} =
      Requests.create_request(
        %{
          "title" => "Parent",
          "current_situation" => "s",
          "goal_description" => "g",
          "expected_output" => "o",
          "kind" => "problem",
          "priority" => 2,
          "target_user_type" => "internal",
          "goal_target" => "interface_view",
          "status" => "in_progress",
          "created_by_id" => user.id,
          "requesting_team_id" => team.id
        },
        user.id
      )

    %{request: request, user: user}
  end

  test "creating an issue sets the project status to the request's status", %{
    request: request
  } do
    enable_in_memory_github()

    assert {:ok, issue} = Requests.create_github_issue_for_request(request)

    assert project_status_option(issue) == "OPT_PROGRESS"

    issue = Requests.get_request_with_github_issue(request.id).github_issue
    assert issue.project_status == "In progress"
  end

  test "cascaded subtask issues get their own status on the project", %{
    request: request,
    user: user
  } do
    {:ok, subtask} = Requests.create_subtask(request, "Child", user.id)
    assert subtask.status == "new"

    enable_in_memory_github()

    assert {:ok, parent_issue} = Requests.create_github_issue_for_request(request)

    child_issue = Requests.get_request_with_github_issue(subtask.id).github_issue
    assert child_issue.project_item_id
    assert project_status_option(parent_issue) == "OPT_PROGRESS"
    assert project_status_option(child_issue) == "OPT_NEW"
  end

  defp enable_in_memory_github do
    Application.put_env(:hermes, :github_adapter, InMemory)

    Application.put_env(:hermes, :github,
      token: "x",
      owner: "dev-org",
      default_repo: "hermes-fake"
    )
  end

  defp project_status_option(issue) do
    {:ok, node_id} = InMemory.get_issue_node_id(issue.owner, issue.repo, issue.number)
    InMemory.project_item_for_issue(node_id).status_option_id
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
