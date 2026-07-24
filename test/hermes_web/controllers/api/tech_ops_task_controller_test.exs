defmodule HermesWeb.Api.TechOpsTaskControllerTest do
  use HermesWeb.ConnCase

  alias Hermes.Accounts
  alias Hermes.TechOps

  setup %{conn: conn} do
    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, dev} =
      Accounts.create_user(%{
        email: "dev@test.com",
        hashed_password: "h",
        role: "dev_team",
        team_id: team.id
      })

    {:ok, member} =
      Accounts.create_user(%{
        email: "member@test.com",
        hashed_password: "h",
        role: "team_member",
        team_id: team.id
      })

    {:ok, dev_token, _} = Accounts.create_api_token(dev, "dev")
    {:ok, member_token, _} = Accounts.create_api_token(member, "member")

    auth = fn c, token -> put_req_header(c, "authorization", "Bearer " <> token) end

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      dev: dev,
      dev_token: dev_token,
      member_token: member_token,
      auth: auth
    }
  end

  describe "authentication" do
    test "401 without a token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tech_ops_tasks")
      assert json_response(conn, 401)["error"]["code"] == "unauthorized"
    end

    test "401 with an invalid token", %{conn: conn, auth: auth} do
      conn = auth.(conn, "hermes_bad") |> get(~p"/api/v1/tech_ops_tasks")
      assert json_response(conn, 401)
    end

    test "401 with an empty bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> get(~p"/api/v1/tech_ops_tasks")

      assert json_response(conn, 401)["error"]["code"] == "unauthorized"
    end

    test "401 with a malformed authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token abc")
        |> get(~p"/api/v1/tech_ops_tasks")

      assert json_response(conn, 401)
    end

    test "403 for a non-tech-team token owner", %{conn: conn, auth: auth, member_token: t} do
      conn = auth.(conn, t) |> get(~p"/api/v1/tech_ops_tasks")
      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end

    test "GET /me returns the token owner", %{conn: conn, auth: auth, dev_token: t, dev: dev} do
      conn = auth.(conn, t) |> get(~p"/api/v1/me")
      assert json_response(conn, 200)["data"]["email"] == dev.email
    end
  end

  describe "index" do
    test "lists tasks", %{conn: conn, auth: auth, dev_token: t} do
      {:ok, _} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "a"
        })

      conn = auth.(conn, t) |> get(~p"/api/v1/tech_ops_tasks")
      assert [%{"reported_problem" => "a"}] = json_response(conn, 200)["data"]
    end

    test "filters by status", %{conn: conn, auth: auth, dev_token: t} do
      {:ok, _} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "open one",
          "status" => "open"
        })

      {:ok, _} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "resolved one",
          "status" => "resolved"
        })

      conn = auth.(conn, t) |> get(~p"/api/v1/tech_ops_tasks?status=resolved")
      assert [%{"reported_problem" => "resolved one"}] = json_response(conn, 200)["data"]
    end
  end

  describe "create" do
    test "reports a task attributed to the token owner", %{
      conn: conn,
      auth: auth,
      dev_token: t,
      dev: dev
    } do
      params = %{"reported_problem" => "Disk full", "issue_origin" => "alert"}
      conn = auth.(conn, t) |> post(~p"/api/v1/tech_ops_tasks", params)
      data = json_response(conn, 201)["data"]
      assert data["reported_problem"] == "Disk full"
      assert data["status"] == "open"
      assert data["responsible"]["id"] == dev.id
    end

    test "422 on missing reported_problem", %{conn: conn, auth: auth, dev_token: t} do
      conn = auth.(conn, t) |> post(~p"/api/v1/tech_ops_tasks", %{})
      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end
  end

  describe "show / update" do
    setup %{dev: dev} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x",
          "responsible_id" => dev.id
        })

      %{task: task}
    end

    test "shows a task", %{conn: conn, auth: auth, dev_token: t, task: task} do
      conn = auth.(conn, t) |> get(~p"/api/v1/tech_ops_tasks/#{task.id}")
      assert json_response(conn, 200)["data"]["id"] == task.id
    end

    test "404 for a missing task", %{conn: conn, auth: auth, dev_token: t} do
      conn = auth.(conn, t) |> get(~p"/api/v1/tech_ops_tasks/999999")
      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end

    test "updates status and resolution", %{conn: conn, auth: auth, dev_token: t, task: task} do
      params = %{"status" => "resolved", "resolution" => "restarted service"}
      conn = auth.(conn, t) |> patch(~p"/api/v1/tech_ops_tasks/#{task.id}", params)
      data = json_response(conn, 200)["data"]
      assert data["status"] == "resolved"
      assert data["resolution"] == "restarted service"
    end
  end
end
