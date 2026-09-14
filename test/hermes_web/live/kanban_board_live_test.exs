defmodule HermesWeb.KanbanBoardLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Requests

  setup %{conn: conn} do
    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "board@example.com",
        hashed_password: "h",
        role: "team_member",
        team_id: team.id
      })

    {:ok, payments} =
      Requests.create_request(%{
        "title" => "Fix payments bug",
        "description" => "Checkout fails",
        "priority" => 2,
        "status" => "pending",
        "created_by_id" => user.id,
        "requesting_team_id" => team.id,
        "assigned_to_team_id" => team.id
      })

    {:ok, onboarding} =
      Requests.create_request(%{
        "title" => "Onboarding revamp",
        "description" => "New welcome flow",
        "priority" => 2,
        "status" => "pending",
        "created_by_id" => user.id,
        "requesting_team_id" => team.id,
        "assigned_to_team_id" => team.id
      })

    %{
      conn: init_test_session(conn, %{user_id: user.id}),
      team: team,
      payments: payments,
      onboarding: onboarding
    }
  end

  defp board_path(team), do: ~p"/boards/#{"#{team.id}_#{team.id}"}"

  defp search(view, term) do
    view
    |> element("#board-search-form")
    |> render_change(%{"search" => term, "priority" => "all", "team" => "all"})

    view
  end

  describe "search" do
    test "filters cards by title", %{
      conn: conn,
      team: team,
      payments: payments,
      onboarding: onboarding
    } do
      {:ok, view, _html} = live(conn, board_path(team))

      assert has_element?(view, "#kanban-card-#{payments.id}")
      assert has_element?(view, "#kanban-card-#{onboarding.id}")

      view = search(view, "payments")

      assert has_element?(view, "#kanban-card-#{payments.id}")
      refute has_element?(view, "#kanban-card-#{onboarding.id}")
      assert_patched(view, board_path(team) <> "?search=payments")
    end

    test "matches description and request id", %{
      conn: conn,
      team: team,
      payments: payments,
      onboarding: onboarding
    } do
      {:ok, view, _html} = live(conn, board_path(team))

      html =
        view
        |> element("#board-search-form")
        |> render_change(%{"search" => "welcome flow", "priority" => "all", "team" => "all"})

      view = search(view, "welcome flow")

      assert has_element?(view, "#kanban-card-#{onboarding.id}")
      refute has_element?(view, "#kanban-card-#{payments.id}")

      view = search(view, "##{payments.id}")

      assert has_element?(view, "#kanban-card-#{payments.id}")
      refute has_element?(view, "#kanban-card-#{onboarding.id}")
    end

    test "search is case insensitive and restores from the url", %{
      conn: conn,
      team: team,
      payments: payments,
      onboarding: onboarding
    } do
      {:ok, view, _html} = live(conn, board_path(team) <> "?search=PAYMENTS")

      assert has_element?(view, "#kanban-card-#{payments.id}")
      refute has_element?(view, "#kanban-card-#{onboarding.id}")

      assert has_element?(view, "#board-search-input[value='PAYMENTS']")
    end

    test "clearing the search restores every card", %{
      conn: conn,
      team: team,
      payments: payments,
      onboarding: onboarding
    } do
      {:ok, view, _html} = live(conn, board_path(team) <> "?search=payments")

      refute has_element?(view, "#kanban-card-#{onboarding.id}")

      view = search(view, "")

      assert has_element?(view, "#kanban-card-#{payments.id}")
      assert has_element?(view, "#kanban-card-#{onboarding.id}")
      assert_patched(view, board_path(team))
    end

    test "task count reflects the search", %{conn: conn, team: team} do
      {:ok, view, _html} = live(conn, board_path(team))
      assert view |> element("#board-task-count") |> render() =~ "2 tasks"

      {:ok, view, _html} = live(conn, board_path(team) <> "?search=payments")
      assert view |> element("#board-task-count") |> render() =~ "1 task"
    end
  end
end
