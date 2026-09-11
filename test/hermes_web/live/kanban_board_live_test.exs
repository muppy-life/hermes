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

  describe "search" do
    test "filters cards by title", %{
      conn: conn,
      team: team,
      payments: payments,
      onboarding: onboarding
    } do
      {:ok, view, html} = live(conn, board_path(team))

      assert html =~ "Fix payments bug"
      assert html =~ "Onboarding revamp"

      html =
        view
        |> form("form[phx-change='apply_filters']", %{"search" => "payments"})
        |> render_change()

      assert html =~ "Fix payments bug"
      refute html =~ "Onboarding revamp"

      assert_patched(view, board_path(team) <> "?search=payments")

      assert render(view) =~ "hermes ##{payments.id}"
      refute render(view) =~ "hermes ##{onboarding.id}"
    end

    test "matches description and request id", %{conn: conn, team: team, onboarding: onboarding} do
      {:ok, view, _html} = live(conn, board_path(team))

      html =
        view
        |> form("form[phx-change='apply_filters']", %{"search" => "welcome flow"})
        |> render_change()

      assert html =~ "Onboarding revamp"
      refute html =~ "Fix payments bug"

      html =
        view
        |> form("form[phx-change='apply_filters']", %{"search" => "##{onboarding.id}"})
        |> render_change()

      assert html =~ "Onboarding revamp"
      refute html =~ "Fix payments bug"
    end

    test "search is case insensitive and survives a page load from params", %{
      conn: conn,
      team: team
    } do
      {:ok, _view, html} = live(conn, board_path(team) <> "?search=PAYMENTS")

      assert html =~ "Fix payments bug"
      refute html =~ "Onboarding revamp"
    end

    test "clearing the search restores every card", %{conn: conn, team: team} do
      {:ok, view, _html} = live(conn, board_path(team) <> "?search=payments")

      html =
        view
        |> form("form[phx-change='apply_filters']", %{"search" => ""})
        |> render_change()

      assert html =~ "Fix payments bug"
      assert html =~ "Onboarding revamp"
      assert_patched(view, board_path(team))
    end

    test "task count reflects the search", %{conn: conn, team: team} do
      {:ok, _view, html} = live(conn, board_path(team))
      assert html =~ "2 tasks"

      {:ok, _view, html} = live(conn, board_path(team) <> "?search=payments")
      assert html =~ "1 task"
    end
  end
end
