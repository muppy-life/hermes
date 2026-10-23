defmodule Hermes.Requests.GitHubBodyPreservationTest do
  use Hermes.DataCase, async: false

  alias Hermes.Accounts
  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.GitHubIssue
  alias Hermes.Services.GitHub
  alias Hermes.Services.GitHub.InMemory

  @manual_body """
  **Context**

  - [ ] Pending charges are processed on contract signature
  """

  setup do
    original_adapter = Application.get_env(:hermes, :github_adapter)
    original_github = Application.get_env(:hermes, :github)

    Application.put_env(:hermes, :github_adapter, InMemory)

    Application.put_env(:hermes, :github,
      token: "x",
      owner: "dev-org",
      default_repo: "hermes-fake",
      api_url: "https://api.github.com"
    )

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

    {:ok, issue} = Requests.create_github_issue_for_request(request)

    %{request: request, user: user, issue: issue}
  end

  test "creating an issue stores the hash of the body Hermes wrote", %{issue: issue} do
    gh = InMemory.get(issue.owner, issue.repo, issue.number)
    assert issue.body_hash == GitHub.body_hash(gh.body)
  end

  describe "adding a subtask to a linked parent" do
    test "keeps a body edited on GitHub and still applies the Epic label", %{
      request: request,
      user: user,
      issue: issue
    } do
      InMemory.set_body(issue.owner, issue.repo, issue.number, @manual_body)

      assert {:ok, _subtask} = Requests.create_subtask(request, "Child", user.id)

      gh = InMemory.get(issue.owner, issue.repo, issue.number)
      assert gh.body == @manual_body
      assert "Epic" in gh.labels
    end
  end

  describe "content sync" do
    test "pushes the new body when GitHub still holds what Hermes wrote", %{
      request: request,
      user: user,
      issue: issue
    } do
      {:ok, _} = Requests.update_request(request, %{"description" => "New text"}, user.id)

      gh = InMemory.get(issue.owner, issue.repo, issue.number)
      assert gh.body =~ "New text"
      assert Repo.get!(GitHubIssue, issue.id).body_hash == GitHub.body_hash(gh.body)
    end

    test "keeps a body edited on GitHub but still syncs the title", %{
      request: request,
      user: user,
      issue: issue
    } do
      InMemory.set_body(issue.owner, issue.repo, issue.number, @manual_body)

      {:ok, _} =
        Requests.update_request(
          request,
          %{"title" => "Renamed", "description" => "New text"},
          user.id
        )

      gh = InMemory.get(issue.owner, issue.repo, issue.number)
      assert gh.body == @manual_body
      assert gh.title =~ "Renamed"
    end

    test "a retry recognises a body whose write response was lost", %{
      request: request,
      user: user,
      issue: issue
    } do
      lost_body = "Body Hermes wrote but never got confirmed"
      InMemory.set_body(issue.owner, issue.repo, issue.number, lost_body)

      issue
      |> Ecto.Changeset.change(pending_body_hash: GitHub.body_hash(lost_body))
      |> Repo.update!()

      {:ok, _} = Requests.update_request(request, %{"description" => "New text"}, user.id)

      gh = InMemory.get(issue.owner, issue.repo, issue.number)
      assert gh.body =~ "New text"

      synced = Repo.get!(GitHubIssue, issue.id)
      assert synced.body_hash == GitHub.body_hash(gh.body)
      assert is_nil(synced.pending_body_hash)
    end

    test "legacy links without a hash only overwrite bodies carrying the Hermes footer", %{
      request: request,
      user: user,
      issue: issue
    } do
      issue |> Ecto.Changeset.change(body_hash: nil) |> Repo.update!()

      {:ok, request} = Requests.update_request(request, %{"description" => "First"}, user.id)
      assert InMemory.get(issue.owner, issue.repo, issue.number).body =~ "First"

      issue |> Ecto.Changeset.change(body_hash: nil) |> Repo.update!()
      InMemory.set_body(issue.owner, issue.repo, issue.number, @manual_body)

      {:ok, _} = Requests.update_request(request, %{"description" => "Second"}, user.id)
      assert InMemory.get(issue.owner, issue.repo, issue.number).body == @manual_body
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
