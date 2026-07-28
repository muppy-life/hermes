defmodule HermesWeb.Api.LookupControllerTest do
  @moduledoc "REST endpoints for the reporter and issue-origin managed vocabularies."
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

    {:ok, token, _} = Accounts.create_api_token(dev, "t")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)

    %{conn: conn}
  end

  describe "reporters" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> delete_req_header("authorization") |> get(~p"/api/v1/reporters")
      assert json_response(conn, 401)
    end

    test "lists reporters alphabetically", %{conn: conn} do
      {:ok, _} = TechOps.create_reporter("Zoe")
      {:ok, _} = TechOps.create_reporter("Ana")

      names =
        conn
        |> get(~p"/api/v1/reporters")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["name"])

      assert names == ["Ana", "Zoe"]
    end

    test "adds a reporter", %{conn: conn} do
      data =
        conn
        |> post(~p"/api/v1/reporters", %{"name" => "On-call"})
        |> json_response(201)
        |> Map.fetch!("data")

      assert data["name"] == "On-call"
      assert data["id"]
    end

    test "adding is idempotent (normalized)", %{conn: conn} do
      first =
        conn
        |> post(~p"/api/v1/reporters", %{"name" => "On-call"})
        |> json_response(201)
        |> Map.fetch!("data")

      second =
        conn
        |> post(~p"/api/v1/reporters", %{"name" => "  on-call "})
        |> json_response(201)
        |> Map.fetch!("data")

      assert first["id"] == second["id"]
    end

    test "422 on a blank name", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/reporters", %{"name" => ""})
      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end
  end

  describe "issue_origins" do
    test "lists and adds", %{conn: conn} do
      {:ok, _} = TechOps.create_issue_origin("Monitoring")

      names =
        conn
        |> get(~p"/api/v1/issue-origins")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["name"])

      assert "Monitoring" in names

      created =
        conn
        |> post(~p"/api/v1/issue-origins", %{"name" => "Deploy"})
        |> json_response(201)
        |> Map.fetch!("data")

      assert created["name"] == "Deploy"
    end
  end
end
