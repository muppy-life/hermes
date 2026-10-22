defmodule HermesWeb.KanbanMyBoardLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Requests

  setup %{conn: conn} do
    {:ok, tech} = Accounts.create_team(%{name: "Tech", description: "d"})
    {:ok, sales} = Accounts.create_team(%{name: "Sales", description: "d"})
    {:ok, ops} = Accounts.create_team(%{name: "Ops", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "mine@example.com",
        hashed_password: "h",
        role: "team_member",
        team_id: tech.id
      })

    tech_request = create_request(user, "Tech to Sales", tech, sales)
    ops_request = create_request(user, "Ops internal", ops, ops)
    hidden_request = create_request(user, "Sales to Ops", sales, ops)

    %{
      conn: init_test_session(conn, %{user_id: user.id}),
      user: user,
      tech: tech,
      ops: ops,
      tech_request: tech_request,
      ops_request: ops_request,
      hidden_request: hidden_request
    }
  end

  defp create_request(user, title, requesting_team, assigned_team) do
    {:ok, request} =
      Requests.create_request(%{
        "title" => title,
        "priority" => 2,
        "status" => "pending",
        "created_by_id" => user.id,
        "requesting_team_id" => requesting_team.id,
        "assigned_to_team_id" => assigned_team.id
      })

    request
  end

  describe "with a single team" do
    test "the card links straight to the board", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards")
      assert has_element?(view, ~s(a#my-board-card[href="/boards/mine"]))
    end

    test "the board shows every request of the user's team without team chips", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine")

      assert has_element?(view, "#kanban-card-#{ctx.tech_request.id}")
      refute has_element?(view, "#kanban-card-#{ctx.ops_request.id}")
      refute has_element?(view, "#kanban-card-#{ctx.hidden_request.id}")
      refute has_element?(view, "#my-board-teams")
    end
  end

  describe "with an extra team" do
    setup ctx do
      {:ok, _} = Accounts.update_user(ctx.user, %{extra_team_ids: [ctx.ops.id]})
      :ok
    end

    test "the board starts with every team selected", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine")

      assert has_element?(view, "#my-board-team-#{ctx.tech.id}.is-active")
      assert has_element?(view, "#my-board-team-#{ctx.ops.id}.is-active")
      assert has_element?(view, "#kanban-card-#{ctx.tech_request.id}")
      assert has_element?(view, "#kanban-card-#{ctx.ops_request.id}")
      assert has_element?(view, "#kanban-card-#{ctx.hidden_request.id}")
    end

    test "toggling a chip narrows and widens the board", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine")

      view |> element("#my-board-team-#{ctx.tech.id}") |> render_click()
      assert_patch(view, ~p"/boards/mine?#{%{teams: "#{ctx.ops.id}"}}")
      refute has_element?(view, "#my-board-team-#{ctx.tech.id}.is-active")
      refute has_element?(view, "#kanban-card-#{ctx.tech_request.id}")
      assert has_element?(view, "#kanban-card-#{ctx.ops_request.id}")

      view |> element("#my-board-team-#{ctx.tech.id}") |> render_click()
      assert_patch(view, ~p"/boards/mine")
      assert has_element?(view, "#kanban-card-#{ctx.tech_request.id}")
    end

    test "the last selected team can't be turned off", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine?#{%{teams: "#{ctx.ops.id}"}}")

      assert has_element?(view, "#my-board-team-#{ctx.ops.id}[disabled]")
      render_click(view, "toggle_team", %{"team-id" => "#{ctx.ops.id}"})
      assert has_element?(view, "#kanban-card-#{ctx.ops_request.id}")
    end

    test "teams outside the user's are ignored", ctx do
      {:ok, other} = Accounts.create_team(%{name: "Other", description: "d"})
      other_request = create_request(ctx.user, "Other internal", other, other)

      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine?#{%{teams: "#{other.id}"}}")

      refute has_element?(view, "#kanban-card-#{other_request.id}")
      assert has_element?(view, "#kanban-card-#{ctx.tech_request.id}")
    end

    test "search keeps the team selection", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/boards/mine?#{%{teams: "#{ctx.ops.id}"}}")

      view
      |> element("#board-search-form")
      |> render_change(%{"search" => "Ops", "priority" => "all", "team" => "all"})

      assert_patch(view, ~p"/boards/mine?#{%{search: "Ops", teams: "#{ctx.ops.id}"}}")
      assert has_element?(view, "#kanban-card-#{ctx.ops_request.id}")
    end
  end
end
