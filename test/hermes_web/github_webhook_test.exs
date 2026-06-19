defmodule HermesWeb.GitHubWebhookTest do
  use HermesWeb.ConnCase, async: false

  alias Hermes.Accounts
  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.GitHubIssue

  @secret "test-webhook-secret"

  setup do
    original = Application.get_env(:hermes, :github)

    Application.put_env(:hermes, :github,
      token: "x",
      owner: "acme",
      default_repo: "main",
      api_url: "https://api.github.com",
      graphql_url: "https://api.github.com/graphql",
      project_id: "PVT_x",
      status_field_id: "FIELD_x",
      webhook_secret: @secret
    )

    on_exit(fn ->
      if original do
        Application.put_env(:hermes, :github, original)
      else
        Application.delete_env(:hermes, :github)
      end
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

    {:ok, link} =
      %GitHubIssue{}
      |> GitHubIssue.changeset(%{
        request_id: request.id,
        owner: "acme",
        repo: "main",
        number: 1,
        url: "https://github.com/acme/main/issues/1",
        project_item_id: "PVTI_1"
      })
      |> Repo.insert()

    {:ok, mapping} =
      Requests.upsert_status_mapping(%{
        "github_option_id" => "OPT_DONE",
        "github_option_name" => "Done",
        "hermes_status" => "completed"
      })

    %{request: request, link: link, mapping: mapping}
  end

  describe "POST /api/github/webhook" do
    test "rejects missing signature", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/github/webhook", "{}")

      assert response(conn, 401) =~ "missing signature"
    end

    test "rejects bad signature", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", "sha256=deadbeef")
        |> post("/api/github/webhook", "{}")

      assert response(conn, 401) =~ "invalid signature"
    end

    test "accepts valid signature on ping", %{conn: conn} do
      body = ~s({"zen":"hello"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "ping")
        |> put_req_header("x-hub-signature-256", "sha256=" <> hmac(body))
        |> post("/api/github/webhook", body)

      assert conn.status == 204
    end

    test "applies status change on projects_v2_item edited", %{conn: conn, request: request} do
      payload = %{
        "action" => "edited",
        "projects_v2_item" => %{"id" => "PVTI_1"},
        "changes" => %{
          "field_value" => %{
            "to" => %{"id" => "OPT_DONE", "name" => "Done"}
          }
        }
      }

      body = Jason.encode!(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "projects_v2_item")
        |> put_req_header("x-hub-signature-256", "sha256=" <> hmac(body))
        |> post("/api/github/webhook", body)

      assert conn.status == 204

      reloaded = Repo.get!(Hermes.Requests.Request, request.id)
      assert reloaded.status == "completed"
    end

    test "logs a tracked change when an issue is closed", %{conn: conn, request: request} do
      conn = post_issue_event(conn, "closed", "closed")

      assert conn.status == 204

      link = Repo.get_by!(GitHubIssue, request_id: request.id)
      assert link.state == "closed"

      change =
        Requests.list_request_changes(request.id)
        |> Enum.find(&(&1.field == "github_issue_state"))

      assert change
      assert change.user_id == nil
      assert change.new_value == "closed"
      assert change.changes["source"] == "github_webhook"
    end

    test "does not log when an issue event leaves the state unchanged", %{
      conn: conn,
      request: request
    } do
      before = Requests.list_request_changes(request.id) |> length()

      # Link starts with state nil; an "edited" event with nil state is a no-op.
      conn = post_issue_event(conn, "edited", nil)
      assert conn.status == 204

      after_count = Requests.list_request_changes(request.id) |> length()
      assert after_count == before
    end

    test "syncs the End date field into the request deadline and logs it", %{
      conn: conn,
      request: request
    } do
      conn = post_date_field_event(conn, "End date", "2026-12-31")
      assert conn.status == 204

      reloaded = Repo.get!(Hermes.Requests.Request, request.id)
      assert reloaded.deadline == ~D[2026-12-31]

      change =
        Requests.list_request_changes(request.id)
        |> Enum.find(&(&1.field == "deadline"))

      assert change
      assert change.new_value == "2026-12-31"
      assert change.changes["event_type"] == "projects_v2_item"
    end

    test "clears the deadline when the End date is removed", %{conn: conn, request: request} do
      {:ok, _} =
        request
        |> Hermes.Requests.Request.changeset(%{deadline: ~D[2026-01-01]})
        |> Repo.update()

      conn = post_date_field_event(conn, "End date", nil)
      assert conn.status == 204

      reloaded = Repo.get!(Hermes.Requests.Request, request.id)
      assert reloaded.deadline == nil
    end

    test "ignores date fields that are not the End date", %{conn: conn, request: request} do
      conn = post_date_field_event(conn, "Start date", "2026-12-31")
      assert conn.status == 204

      reloaded = Repo.get!(Hermes.Requests.Request, request.id)
      assert reloaded.deadline == nil
    end
  end

  defp post_issue_event(conn, action, state) do
    payload = %{
      "action" => action,
      "issue" => %{"number" => 1, "state" => state},
      "repository" => %{"name" => "main", "owner" => %{"login" => "acme"}}
    }

    post_webhook(conn, "issues", payload)
  end

  defp post_date_field_event(conn, field_name, to) do
    payload = %{
      "action" => "edited",
      "projects_v2_item" => %{"id" => "PVTI_1"},
      "changes" => %{
        "field_value" => %{
          "field_type" => "date",
          "field_name" => field_name,
          "to" => to
        }
      }
    }

    post_webhook(conn, "projects_v2_item", payload)
  end

  defp post_webhook(conn, event, payload) do
    body = Jason.encode!(payload)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-hub-signature-256", "sha256=" <> hmac(body))
    |> post("/api/github/webhook", body)
  end

  defp hmac(body) do
    :crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower)
  end
end
