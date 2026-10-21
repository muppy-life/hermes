defmodule HermesWeb.Admin.TeamLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Accounts.Team

  setup %{conn: conn} do
    {:ok, tech} = Accounts.create_team(%{name: "Tech", description: "d"})
    {:ok, ops} = Accounts.create_team(%{name: "Ops", description: "d"})

    {:ok, admin} =
      Accounts.create_user(%{
        email: "admin@example.com",
        hashed_password: "h",
        role: "admin",
        is_admin: true,
        team_id: tech.id
      })

    %{conn: init_test_session(conn, %{user_id: admin.id}), admin: admin, ops: ops}
  end

  defp delete_team(conn, team) do
    {:ok, view, _html} = live(conn, ~p"/admin/teams")

    view
    |> element("button[phx-click='open_delete_modal'][phx-value-id='#{team.id}']")
    |> render_click()

    view |> element("button[phx-click='confirm_delete']") |> render_click()
  end

  test "a team whose only members have it as an extra team cannot be deleted", ctx do
    {:ok, _} = Accounts.update_user(ctx.admin, %{extra_team_ids: [ctx.ops.id]})

    delete_team(ctx.conn, ctx.ops)

    assert Hermes.Repo.get(Team, ctx.ops.id)
    assert Accounts.team_ids(ctx.admin) == [ctx.admin.team_id, ctx.ops.id]
  end

  test "a team without members can be deleted", ctx do
    delete_team(ctx.conn, ctx.ops)

    refute Hermes.Repo.get(Team, ctx.ops.id)
  end
end
