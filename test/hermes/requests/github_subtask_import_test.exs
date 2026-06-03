defmodule Hermes.Requests.GitHubSubtaskImportTest do
  use Hermes.DataCase, async: false

  alias Hermes.Accounts
  alias Hermes.Requests
  alias Hermes.Services.GitHub.InMemory

  setup do
    original_adapter = Application.get_env(:hermes, :github_adapter)
    original_github = Application.get_env(:hermes, :github)

    # Drive the in-memory adapter so we exercise the full sub-issue path
    # without hitting the network.
    Application.put_env(:hermes, :github_adapter, InMemory)

    Application.put_env(:hermes, :github,
      token: "x",
      owner: "dev-org",
      default_repo: "hermes-fake",
      api_url: "https://api.github.com"
    )

    case Process.whereis(InMemory) do
      nil -> {:ok, _} = InMemory.start_link([])
      _pid -> InMemory.reset()
    end

    on_exit(fn ->
      restore_env(:github_adapter, original_adapter)
      restore_env(:github, original_github)
    end)

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
          "status" => "pending",
          "created_by_id" => user.id,
          "requesting_team_id" => team.id
        },
        user.id
      )

    %{request: request, user: user}
  end

  # Seeds a parent GitHub issue with the given child sub-issues attached, and
  # links it to the Hermes request. Returns the linked request.
  defp seed_linked_parent_with_subs(request, children) do
    {:ok, %{number: parent_num}} =
      InMemory.create_issue(%{
        owner: "dev-org",
        repo: "hermes-fake",
        title: "Parent issue",
        body: "b",
        labels: []
      })

    {:ok, parent_node} = InMemory.get_issue_node_id("dev-org", "hermes-fake", parent_num)

    Enum.each(children, fn %{title: title, state: state} ->
      {:ok, %{number: n}} =
        InMemory.create_issue(%{
          owner: "dev-org",
          repo: "hermes-fake",
          title: title,
          body: "b",
          labels: []
        })

      if state == "closed", do: InMemory.set_state("dev-org", "hermes-fake", n, "closed")
      {:ok, child_node} = InMemory.get_issue_node_id("dev-org", "hermes-fake", n)
      {:ok, _} = InMemory.add_sub_issue(parent_node, child_node)
    end)

    {:ok, _issue} = Requests.link_github_issue(request, Integer.to_string(parent_num))
    Requests.get_request_with_github_issue(request.id)
  end

  test "list_linkable_github_subtasks returns unimported remote sub-issues", %{request: request} do
    request =
      seed_linked_parent_with_subs(request, [
        %{title: "Build login", state: "open"},
        %{title: "Session expiry", state: "closed"}
      ])

    assert {:ok, subs} = Requests.list_linkable_github_subtasks(request)
    titles = Enum.map(subs, & &1.title) |> Enum.sort()
    assert titles == ["Build login", "Session expiry"]
  end

  test "import_github_subtasks creates subtasks linked to the existing issues", %{
    request: request,
    user: user
  } do
    request =
      seed_linked_parent_with_subs(request, [
        %{title: "Build login", state: "open"},
        %{title: "Session expiry", state: "closed"}
      ])

    {:ok, subs} = Requests.list_linkable_github_subtasks(request)
    issues_before = length(InMemory.list_issues())

    assert {:ok, 2} = Requests.import_github_subtasks(request, subs, user.id)

    # No new GitHub issues were created — only the parent + 2 children exist.
    assert length(InMemory.list_issues()) == issues_before

    subtasks = Requests.list_subtasks(request.id)
    assert length(subtasks) == 2

    by_title = Map.new(subtasks, &{&1.title, &1})
    assert by_title["Build login"].status == "new"
    assert by_title["Session expiry"].status == "completed"

    # Each subtask is linked to its existing GitHub issue.
    Enum.each(subtasks, fn st ->
      assert Requests.get_request_with_github_issue(st.id).github_issue
    end)

    # Re-importing the same set is a no-op (already imported).
    assert {:ok, 0} = Requests.import_github_subtasks(request, subs, user.id)
    assert length(Requests.list_subtasks(request.id)) == 2
  end

  test "import_github_subtasks errors when the parent is not linked", %{
    request: request,
    user: user
  } do
    assert {:error, :parent_not_linked} =
             Requests.import_github_subtasks(request, [], user.id)
  end

  test "create_subtask under a linked parent does not create a GitHub issue", %{
    request: request,
    user: user
  } do
    request = seed_linked_parent_with_subs(request, [])
    issues_before = length(InMemory.list_issues())

    {:ok, subtask} = Requests.create_subtask(request, "Hermes-only subtask", user.id)

    # No new GitHub issue was created for the subtask.
    assert length(InMemory.list_issues()) == issues_before
    # And the subtask stays Hermes-only (no linked GitHub issue row).
    refute Requests.get_request_with_github_issue(subtask.id).github_issue
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
