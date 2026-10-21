defmodule HermesWeb.KanbanExtraTeamsLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Requests

  setup %{conn: conn} do
    {:ok, tech} = Accounts.create_team(%{name: "Tech", description: "d"})
    {:ok, sales} = Accounts.create_team(%{name: "Sales", description: "d"})
    {:ok, ops} = Accounts.create_team(%{name: "Ops", description: "d"})

    {:ok, agent} =
      Accounts.create_user(%{
        email: "agent@example.com",
        hashed_password: "h",
        role: "team_member",
        team_id: tech.id
      })

    {:ok, request} =
      Requests.create_request(%{
        "title" => "Sales to Ops handoff",
        "priority" => 2,
        "status" => "pending",
        "created_by_id" => agent.id,
        "requesting_team_id" => sales.id,
        "assigned_to_team_id" => ops.id
      })

    %{
      conn: init_test_session(conn, %{user_id: agent.id}),
      agent: agent,
      sales: sales,
      ops: ops,
      request: request,
      board_id: "#{min(sales.id, ops.id)}_#{max(sales.id, ops.id)}",
      board_path: ~p"/boards/#{"#{min(sales.id, ops.id)}_#{max(sales.id, ops.id)}"}"
    }
  end

  test "without the extra team the board is hidden and inaccessible", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/boards")
    refute has_element?(view, "#board-card-#{ctx.board_id}")

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(ctx.conn, ctx.board_path)
  end

  test "with the extra team the board is listed and shows its cards", ctx do
    {:ok, _} = Accounts.update_user(ctx.agent, %{extra_team_ids: [ctx.ops.id]})

    {:ok, view, _html} = live(ctx.conn, ~p"/boards")
    assert has_element?(view, "#board-card-#{ctx.board_id}", "Ops ↔ Sales")

    {:ok, view, _html} = live(ctx.conn, ctx.board_path)
    assert has_element?(view, "#kanban-card-#{ctx.request.id}")
  end

  test "board metrics require access", ctx do
    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             live(ctx.conn, ctx.board_path <> "/metrics")

    {:ok, _} = Accounts.update_user(ctx.agent, %{extra_team_ids: [ctx.ops.id]})
    assert {:ok, _view, _html} = live(ctx.conn, ctx.board_path <> "/metrics")
  end
end
