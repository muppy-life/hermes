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
    test "creates an issue, inserts a row, and posts a link comment", %{request: request} do
      test_pid = self()

      stub_github(fn conn ->
        cond do
          conn.method == "POST" and conn.request_path == "/repos/acme/main/issues" ->
            json(conn, 201, %{
              "number" => 42,
              "html_url" => "https://github.com/acme/main/issues/42"
            })

          conn.request_path == "/repos/acme/main/issues/42/comments" ->
            send(test_pid, {:comment, read_body(conn)})
            json(conn, 201, %{"id" => 9001})
        end
      end)

      assert {:ok, issue} = Requests.create_github_issue_for_request(request)
      assert issue.owner == "acme"
      assert issue.repo == "main"
      assert issue.number == 42
      assert issue.url == "https://github.com/acme/main/issues/42"
      assert issue.request_id == request.id
      assert issue.link_comment_id == 9001

      assert_received {:comment, body}
      assert body =~ "Linked to Hermes"
      assert body =~ "hermes:link:#{request.id}"
    end

    test "rejects when already linked", %{request: request} do
      stub_github(fn conn ->
        json(conn, 201, %{
          "number" => 1,
          "id" => 1,
          "html_url" => "https://github.com/acme/main/issues/1"
        })
      end)

      assert {:ok, _} = Requests.create_github_issue_for_request(request)
      assert {:error, :already_linked} = Requests.create_github_issue_for_request(request)
    end

    test "passes :repo override", %{request: request} do
      stub_github(fn conn ->
        assert conn.request_path in [
                 "/repos/acme/other/issues",
                 "/repos/acme/other/issues/7/comments"
               ]

        json(conn, 201, %{
          "number" => 7,
          "id" => 7,
          "html_url" => "https://github.com/acme/other/issues/7"
        })
      end)

      assert {:ok, issue} = Requests.create_github_issue_for_request(request, repo: "other")
      assert issue.repo == "other"
    end
  end

  describe "link_github_issue/2" do
    test "links existing issue using bare number and posts a link comment", %{request: request} do
      test_pid = self()

      stub_github(fn conn ->
        cond do
          conn.method == "GET" and conn.request_path == "/repos/acme/main/issues/55" ->
            json(conn, 200, %{
              "number" => 55,
              "html_url" => "https://github.com/acme/main/issues/55",
              "state" => "open"
            })

          conn.request_path == "/repos/acme/main/issues/55/comments" ->
            send(test_pid, {:comment, read_body(conn)})
            json(conn, 201, %{"id" => 12_345})
        end
      end)

      assert {:ok, issue} = Requests.link_github_issue(request, "55")
      assert issue.number == 55
      assert issue.repo == "main"
      assert issue.state == "open"
      assert issue.link_comment_id == 12_345

      assert_received {:comment, body}
      assert body =~ "hermes:link:#{request.id}"
    end

    test "links via full URL with non-default repo", %{request: request} do
      stub_github(fn conn ->
        cond do
          conn.method == "GET" ->
            assert conn.request_path == "/repos/acme/other/issues/3"

            json(conn, 200, %{
              "number" => 3,
              "html_url" => "https://github.com/acme/other/issues/3",
              "state" => "closed"
            })

          conn.request_path == "/repos/acme/other/issues/3/comments" ->
            json(conn, 201, %{"id" => 3})
        end
      end)

      assert {:ok, issue} =
               Requests.link_github_issue(
                 request,
                 "https://github.com/acme/other/issues/3"
               )

      assert issue.repo == "other"
      assert issue.state == "closed"
    end

    test "rejects garbage references", %{request: request} do
      stub_github(fn conn -> Plug.Conn.resp(conn, 200, "{}") end)
      assert {:error, :invalid_reference} = Requests.link_github_issue(request, "nope")
    end
  end

  describe "unlink_github_issue/1" do
    test "deletes the link row and the link comment", %{request: request} do
      test_pid = self()

      stub_github(fn conn ->
        cond do
          conn.method == "POST" and conn.request_path == "/repos/acme/main/issues" ->
            json(conn, 201, %{
              "number" => 9,
              "html_url" => "https://github.com/acme/main/issues/9"
            })

          conn.request_path == "/repos/acme/main/issues/9/comments" ->
            json(conn, 201, %{"id" => 777})

          conn.method == "DELETE" and
              conn.request_path == "/repos/acme/main/issues/comments/777" ->
            send(test_pid, :comment_deleted)
            json(conn, 204, %{})
        end
      end)

      {:ok, _issue} = Requests.create_github_issue_for_request(request)
      assert {:ok, _} = Requests.unlink_github_issue(request)
      assert_received :comment_deleted
      assert {:error, :not_linked} = Requests.unlink_github_issue(request)
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

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp read_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    body
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
