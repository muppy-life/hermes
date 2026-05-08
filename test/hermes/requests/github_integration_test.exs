defmodule Hermes.Requests.GitHubIntegrationTest do
  use Hermes.DataCase, async: false

  alias Hermes.Accounts
  alias Hermes.Requests

  setup do
    original_github = Application.get_env(:hermes, :github)
    original_opts = Application.get_env(:hermes, :github_req_options)

    on_exit(fn ->
      restore_env(:github, original_github)
      restore_env(:github_req_options, original_opts)
    end)

    # Disable integration during fixture setup so the create-request hook
    # does not call the real GitHub API. Tests re-enable explicitly.
    Application.put_env(:hermes, :github,
      token: nil,
      owner: nil,
      default_repo: nil,
      api_url: "https://api.github.com"
    )

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
          "title" => "T",
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

    %{request: request}
  end

  describe "create_github_issue_for_request/1" do
    test "creates an issue and persists number+url", %{request: request} do
      stub_github(fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/acme/main/issues"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          201,
          Jason.encode!(%{"number" => 42, "html_url" => "https://github.com/acme/main/issues/42"})
        )
      end)

      assert {:ok, updated} = Requests.create_github_issue_for_request(request)
      assert updated.github_issue_number == 42
      assert updated.github_issue_url == "https://github.com/acme/main/issues/42"
    end

    test "rejects when already linked", %{request: request} do
      {:ok, request} =
        Requests.update_request(request, %{
          "github_issue_number" => 1,
          "github_issue_url" => "x"
        })

      assert {:error, :already_linked} = Requests.create_github_issue_for_request(request)
    end
  end

  describe "link_github_issue/2" do
    test "links existing issue using bare number", %{request: request} do
      stub_github(fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/repos/acme/main/issues/55"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"number" => 55, "html_url" => "https://github.com/acme/main/issues/55"})
        )
      end)

      assert {:ok, updated} = Requests.link_github_issue(request, "55")
      assert updated.github_issue_number == 55
    end

    test "links via full URL and stores repo override when different", %{request: request} do
      stub_github(fn conn ->
        assert conn.request_path == "/repos/acme/other/issues/3"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"number" => 3, "html_url" => "https://github.com/acme/other/issues/3"})
        )
      end)

      assert {:ok, updated} =
               Requests.link_github_issue(
                 request,
                 "https://github.com/acme/other/issues/3"
               )

      assert updated.github_issue_number == 3
      assert updated.github_repo == "other"
    end

    test "rejects garbage references", %{request: request} do
      assert {:error, :invalid_reference} = Requests.link_github_issue(request, "nope")
    end
  end

  defp stub_github(fun) do
    Application.put_env(:hermes, :github,
      token: "test-token",
      owner: "acme",
      default_repo: "main",
      api_url: "https://api.github.com"
    )

    Application.put_env(:hermes, :github_req_options, plug: fun)
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
