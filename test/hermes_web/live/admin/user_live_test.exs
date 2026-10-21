defmodule HermesWeb.Admin.UserLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts

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

    {:ok, agent} =
      Accounts.create_user(%{
        email: "agent@example.com",
        hashed_password: "h",
        role: "team_member",
        team_id: tech.id
      })

    %{conn: init_test_session(conn, %{user_id: admin.id}), tech: tech, ops: ops, agent: agent}
  end

  defp edit(view, user) do
    view |> element("button[phx-value-id='#{user.id}']", "Edit") |> render_click()
    view
  end

  defp save(view, extra_team_id) do
    view
    |> form("#user-form", %{"user" => %{"extra_team_ids" => [extra_team_id]}})
    |> render_submit()
  end

  test "the extra team select is revealed on demand", %{conn: conn, agent: agent} do
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    edit(view, agent)

    refute has_element?(view, "#user_extra_team_id")
    view |> element("#show-extra-team") |> render_click()

    assert has_element?(view, "#user_extra_team_id")
    refute has_element?(view, "#show-extra-team")
  end

  test "admins can set, replace and clear the extra team", ctx do
    {:ok, sales} = Accounts.create_team(%{name: "Sales", description: "d"})
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/users")

    view |> edit(ctx.agent) |> element("#show-extra-team") |> render_click()
    save(view, to_string(ctx.ops.id))

    assert Accounts.team_ids(ctx.agent) == [ctx.tech.id, ctx.ops.id]
    assert has_element?(view, "#user-#{ctx.agent.id}-extra-team-#{ctx.ops.id}", "+ Ops")

    # An existing extra team shows the select straight away, preselected
    edit(view, ctx.agent)
    refute has_element?(view, "#show-extra-team")
    assert has_element?(view, "#user_extra_team_id option[value='#{ctx.ops.id}'][selected]")

    save(view, to_string(sales.id))
    assert Accounts.team_ids(ctx.agent) == [ctx.tech.id, sales.id]

    edit(view, ctx.agent)
    save(view, "")
    assert Accounts.team_ids(ctx.agent) == [ctx.tech.id]
  end

  test "the primary team is not offered as an extra team", %{conn: conn, tech: tech, agent: agent} do
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    view |> edit(agent) |> element("#show-extra-team") |> render_click()

    refute has_element?(view, "#user_extra_team_id option[value='#{tech.id}']")
  end
end
