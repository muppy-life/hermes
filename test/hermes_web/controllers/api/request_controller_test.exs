defmodule HermesWeb.Api.RequestControllerTest do
  use HermesWeb.ConnCase

  alias Hermes.Accounts
  alias Hermes.Requests

  setup %{conn: conn} do
    {:ok, team} = Accounts.create_team(%{name: "Dev Team", description: "d"})
    {:ok, other_team} = Accounts.create_team(%{name: "Other Team", description: "d"})

    {:ok, dev} =
      Accounts.create_user(%{
        email: "dev@test.com",
        hashed_password: "h",
        role: "dev_team",
        team_id: team.id
      })

    {:ok, token, _} = Accounts.create_api_token(dev, "dev")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)

    %{conn: conn, dev: dev, team: team, other_team: other_team}
  end

  defp create_request(attrs) do
    base = %{
      "title" => "T",
      "priority" => 2,
      "status" => "pending"
    }

    {:ok, request} = Requests.create_request(Map.merge(base, attrs))
    request
  end

  describe "index" do
    test "lists requests where the caller's team is requesting or assigned", %{
      conn: conn,
      dev: dev,
      team: team,
      other_team: other_team
    } do
      mine =
        create_request(%{
          "title" => "Mine",
          "created_by_id" => dev.id,
          "requesting_team_id" => team.id
        })

      assigned =
        create_request(%{
          "title" => "Assigned to me",
          "created_by_id" => dev.id,
          "requesting_team_id" => other_team.id,
          "assigned_to_team_id" => team.id
        })

      _theirs =
        create_request(%{
          "title" => "Not mine",
          "created_by_id" => dev.id,
          "requesting_team_id" => other_team.id
        })

      titles =
        conn
        |> get(~p"/api/v1/requests")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["title"])

      assert "Mine" in titles
      assert "Assigned to me" in titles
      refute "Not mine" in titles
      assert length(titles) == 2
      assert mine.id && assigned.id
    end

    test "filters by status", %{conn: conn, dev: dev, team: team} do
      create_request(%{
        "title" => "P",
        "created_by_id" => dev.id,
        "requesting_team_id" => team.id,
        "status" => "pending"
      })

      create_request(%{
        "title" => "C",
        "created_by_id" => dev.id,
        "requesting_team_id" => team.id,
        "status" => "completed"
      })

      data =
        conn
        |> get(~p"/api/v1/requests?status=completed")
        |> json_response(200)
        |> Map.fetch!("data")

      assert [%{"title" => "C"}] = data
    end
  end

  describe "show" do
    test "returns a request in the caller's team", %{conn: conn, dev: dev, team: team} do
      req =
        create_request(%{
          "title" => "Visible",
          "created_by_id" => dev.id,
          "requesting_team_id" => team.id
        })

      data =
        conn |> get(~p"/api/v1/requests/#{req.id}") |> json_response(200) |> Map.fetch!("data")

      assert data["id"] == req.id
      assert data["title"] == "Visible"
    end

    test "404 for a request outside the caller's team (no info leak)", %{
      conn: conn,
      dev: dev,
      other_team: other_team
    } do
      req =
        create_request(%{
          "title" => "Hidden",
          "created_by_id" => dev.id,
          "requesting_team_id" => other_team.id
        })

      conn = get(conn, ~p"/api/v1/requests/#{req.id}")
      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end

    test "404 for a nonexistent request", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/requests/999999")
      assert json_response(conn, 404)
    end
  end

  describe "nil-team token owner" do
    setup %{conn: conn} do
      # A tech-team user whose team_id is nil must not see unassigned requests.
      # Force team_id to nil directly (the changeset requires it on create).
      {:ok, user} =
        Accounts.create_user(%{
          email: "noteam@test.com",
          hashed_password: "h",
          role: "admin",
          is_admin: true,
          team_id:
            Accounts.create_team(%{name: "tmp", description: "d"}) |> elem(1) |> Map.fetch!(:id)
        })

      {:ok, user} = user |> Ecto.Changeset.change(%{team_id: nil}) |> Hermes.Repo.update()
      {:ok, token, _} = Accounts.create_api_token(user, "noteam")

      %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
    end

    test "index returns empty for a teamless owner", %{conn: conn, dev: dev, team: team} do
      create_request(%{
        "title" => "Someone's",
        "created_by_id" => dev.id,
        "requesting_team_id" => team.id
      })

      assert conn |> get(~p"/api/v1/requests") |> json_response(200) |> Map.fetch!("data") == []
    end

    test "show 404s for a teamless owner", %{conn: conn, dev: dev, team: team} do
      req =
        create_request(%{
          "title" => "Someone's",
          "created_by_id" => dev.id,
          "requesting_team_id" => team.id
        })

      assert conn |> get(~p"/api/v1/requests/#{req.id}") |> json_response(404)
    end
  end

  test "requires authentication", %{conn: conn} do
    conn = conn |> delete_req_header("authorization") |> get(~p"/api/v1/requests")
    assert json_response(conn, 401)
  end
end
