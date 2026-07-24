defmodule HermesWeb.Api.MCPControllerTest do
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

    {:ok, token, _} = Accounts.create_api_token(dev, "mcp")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)

    %{conn: conn, dev: dev}
  end

  defp rpc(conn, body), do: post(conn, ~p"/mcp", body)

  describe "handshake" do
    test "initialize returns server info and capabilities", %{conn: conn} do
      resp = rpc(conn, %{jsonrpc: "2.0", id: 1, method: "initialize", params: %{}})
      body = json_response(resp, 200)
      assert body["id"] == 1
      assert body["result"]["serverInfo"]["name"] == "hermes-tech-ops"
      assert body["result"]["capabilities"]["tools"] == %{}
    end

    test "notifications/initialized returns 202 with no body", %{conn: conn} do
      resp = rpc(conn, %{jsonrpc: "2.0", method: "notifications/initialized"})
      assert resp.status == 202
      assert resp.resp_body == ""
    end

    test "unauthenticated request is rejected", %{conn: conn} do
      resp =
        conn
        |> delete_req_header("authorization")
        |> rpc(%{jsonrpc: "2.0", id: 1, method: "initialize"})

      assert json_response(resp, 401)
    end
  end

  describe "tools/list" do
    test "lists all tech-ops tools with input schemas", %{conn: conn} do
      resp = rpc(conn, %{jsonrpc: "2.0", id: 2, method: "tools/list"})
      tools = json_response(resp, 200)["result"]["tools"]
      names = Enum.map(tools, & &1["name"])

      assert "report_tech_ops_task" in names
      assert "resolve_tech_ops_task" in names
      assert "list_requests" in names
      assert "get_request" in names
      assert Enum.all?(tools, &is_map(&1["inputSchema"]))
    end
  end

  describe "tools/call requests (read-only, team-scoped)" do
    setup %{dev: dev} do
      %{team_id: team_id} = dev
      {:ok, other_team} = Accounts.create_team(%{name: "Other", description: "d"})

      {:ok, mine} =
        Hermes.Requests.create_request(%{
          "title" => "Mine",
          "priority" => 2,
          "status" => "pending",
          "created_by_id" => dev.id,
          "requesting_team_id" => team_id
        })

      {:ok, theirs} =
        Hermes.Requests.create_request(%{
          "title" => "Theirs",
          "priority" => 2,
          "status" => "pending",
          "created_by_id" => dev.id,
          "requesting_team_id" => other_team.id
        })

      %{mine: mine, theirs: theirs}
    end

    test "list_requests only returns the caller's team requests", %{
      conn: conn,
      mine: mine,
      theirs: theirs
    } do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 10,
          method: "tools/call",
          params: %{name: "list_requests", arguments: %{}}
        })

      payload =
        json_response(resp, 200)["result"]["content"]
        |> hd()
        |> Map.fetch!("text")
        |> Jason.decode!()

      ids = Enum.map(payload["requests"], & &1["id"])
      assert mine.id in ids
      refute theirs.id in ids
    end

    test "get_request returns a visible request", %{conn: conn, mine: mine} do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 11,
          method: "tools/call",
          params: %{name: "get_request", arguments: %{id: mine.id}}
        })

      result = json_response(resp, 200)["result"]
      assert result["isError"] == false
      payload = result["content"] |> hd() |> Map.fetch!("text") |> Jason.decode!()
      assert payload["id"] == mine.id
    end

    test "get_request hides requests outside the caller's team", %{conn: conn, theirs: theirs} do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 12,
          method: "tools/call",
          params: %{name: "get_request", arguments: %{id: theirs.id}}
        })

      assert json_response(resp, 200)["result"]["isError"] == true
    end
  end

  describe "tools/call" do
    test "report_tech_ops_task creates a task attributed to the caller", %{conn: conn, dev: dev} do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: %{
            name: "report_tech_ops_task",
            arguments: %{reported_problem: "API latency spike", issue_origin: "AppSignal"}
          }
        })

      result = json_response(resp, 200)["result"]
      assert result["isError"] == false
      payload = result["content"] |> hd() |> Map.fetch!("text") |> Jason.decode!()
      assert payload["reported_problem"] == "API latency spike"
      assert payload["status"] == "open"
      assert payload["responsible"]["id"] == dev.id
    end

    test "resolve_tech_ops_task completes a task", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x"
        })

      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 4,
          method: "tools/call",
          params: %{
            name: "resolve_tech_ops_task",
            arguments: %{id: task.id, resolution: "patched"}
          }
        })

      payload =
        json_response(resp, 200)["result"]["content"]
        |> hd()
        |> Map.fetch!("text")
        |> Jason.decode!()

      assert payload["status"] == "resolved"
      assert payload["resolution"] == "patched"
    end

    test "returns isError for a missing task", %{conn: conn} do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 5,
          method: "tools/call",
          params: %{name: "get_tech_ops_task", arguments: %{id: 999_999}}
        })

      assert json_response(resp, 200)["result"]["isError"] == true
    end

    test "unknown tool returns isError", %{conn: conn} do
      resp =
        rpc(conn, %{
          jsonrpc: "2.0",
          id: 6,
          method: "tools/call",
          params: %{name: "nope", arguments: %{}}
        })

      assert json_response(resp, 200)["result"]["isError"] == true
    end
  end

  describe "errors" do
    test "unknown method returns -32601", %{conn: conn} do
      resp = rpc(conn, %{jsonrpc: "2.0", id: 7, method: "does/not/exist"})
      assert json_response(resp, 200)["error"]["code"] == -32_601
    end
  end
end
