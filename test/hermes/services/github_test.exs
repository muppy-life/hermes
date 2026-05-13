defmodule Hermes.Services.GitHubTest do
  use ExUnit.Case, async: false

  alias Hermes.Requests.Request
  alias Hermes.Services.GitHub

  describe "parse_issue_reference/1" do
    test "parses bare integer" do
      assert {:ok, {nil, nil, 42}} = GitHub.parse_issue_reference("42")
    end

    test "parses issue with leading hash" do
      assert {:ok, {nil, nil, 7}} = GitHub.parse_issue_reference("#7")
    end

    test "parses full URL" do
      assert {:ok, {"acme", "repo", 13}} =
               GitHub.parse_issue_reference("https://github.com/acme/repo/issues/13")
    end

    test "rejects garbage" do
      assert {:error, :invalid_reference} = GitHub.parse_issue_reference("not a ref")
    end
  end

  describe "render_body/1" do
    test "renders sections from a request" do
      request = %Request{
        id: 99,
        title: "Login flaky",
        kind: :problem,
        priority: 3,
        target_user_type: :internal,
        goal_target: :interface_view,
        current_situation: "users randomly logged out",
        goal_description: "stable session",
        expected_output: "no logouts under load"
      }

      body = GitHub.render_body(request)

      assert body =~ "### Kind"
      assert body =~ "Problem"
      assert body =~ "### Priority"
      assert body =~ "Important"
      assert body =~ "### Current situation"
      assert body =~ "users randomly logged out"
      assert body =~ "Synced from Hermes request #99"
    end

    test "skips empty sections" do
      request = %Request{id: 1, title: "T", goal_description: "g"}
      body = GitHub.render_body(request)

      refute body =~ "### Current situation"
      assert body =~ "### Goal"
    end
  end

  describe "default_target/0" do
    setup do
      original = Application.get_env(:hermes, :github)

      on_exit(fn ->
        if original do
          Application.put_env(:hermes, :github, original)
        else
          Application.delete_env(:hermes, :github)
        end
      end)

      :ok
    end

    test "returns configured owner/default_repo" do
      Application.put_env(:hermes, :github,
        token: "x",
        owner: "acme",
        default_repo: "main",
        api_url: "https://api.github.com"
      )

      assert {:ok, {"acme", "main"}} = GitHub.default_target()
    end

    test "errors without owner" do
      Application.put_env(:hermes, :github,
        token: "x",
        owner: nil,
        default_repo: "main",
        api_url: "https://api.github.com"
      )

      assert {:error, :missing_config} = GitHub.default_target()
    end
  end

  describe "create_issue/1 (HTTP stubbed)" do
    setup do
      original_github = Application.get_env(:hermes, :github)
      original_opts = Application.get_env(:hermes, :github_req_options)

      Application.put_env(:hermes, :github,
        token: "test-token",
        owner: "acme",
        default_repo: "main",
        api_url: "https://api.github.com"
      )

      on_exit(fn ->
        restore_env(:github, original_github)
        restore_env(:github_req_options, original_opts)
      end)

      :ok
    end

    test "POSTs to /issues and returns number+url" do
      Application.put_env(:hermes, :github_req_options,
        plug: fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/repos/acme/main/issues"

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          assert decoded["title"] =~ "Hermes"
          assert is_binary(decoded["body"])

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            201,
            Jason.encode!(%{
              "number" => 99,
              "html_url" => "https://github.com/acme/main/issues/99"
            })
          )
        end
      )

      request = %Request{
        id: 5,
        title: "ttl",
        kind: :problem,
        priority: 2,
        goal_description: "g"
      }

      assert {:ok,
              %{
                owner: "acme",
                repo: "main",
                number: 99,
                url: "https://github.com/acme/main/issues/99"
              }} = GitHub.create_issue(request)
    end

    test "honors :repo override" do
      Application.put_env(:hermes, :github_req_options,
        plug: fn conn ->
          assert conn.request_path == "/repos/acme/other/issues"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            201,
            Jason.encode!(%{
              "number" => 1,
              "html_url" => "https://github.com/acme/other/issues/1"
            })
          )
        end
      )

      request = %Request{id: 5, title: "t", goal_description: "g"}

      assert {:ok, %{repo: "other"}} = GitHub.create_issue(request, repo: "other")
    end

    test "returns http error on non-2xx" do
      Application.put_env(:hermes, :github_req_options,
        plug: fn conn ->
          Plug.Conn.resp(conn, 422, ~s({"message":"validation failed"}))
        end
      )

      request = %Request{id: 5, title: "t", goal_description: "g"}
      assert {:error, {:http_error, 422, _}} = GitHub.create_issue(request)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:hermes, key)
  defp restore_env(key, value), do: Application.put_env(:hermes, key, value)
end
