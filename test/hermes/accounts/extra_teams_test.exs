defmodule Hermes.Accounts.ExtraTeamsTest do
  use Hermes.DataCase

  alias Hermes.Accounts
  alias Hermes.Kanbans
  alias Hermes.MCP.Tools
  alias Hermes.Requests

  setup do
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

    {:ok, seller} =
      Accounts.create_user(%{
        email: "seller@example.com",
        hashed_password: "h",
        role: "team_member",
        team_id: sales.id
      })

    {:ok, request} =
      Requests.create_request(%{
        "title" => "Sales to Ops handoff",
        "priority" => 2,
        "status" => "pending",
        "created_by_id" => seller.id,
        "requesting_team_id" => sales.id,
        "assigned_to_team_id" => ops.id
      })

    %{tech: tech, sales: sales, ops: ops, agent: agent, request: request}
  end

  defp add_extra_teams(user, teams) do
    {:ok, user} = Accounts.update_user(user, %{extra_team_ids: Enum.map(teams, & &1.id)})
    user
  end

  describe "extra team memberships" do
    test "team_ids/1 lists the primary team first", %{tech: tech, sales: sales, agent: agent} do
      assert Accounts.team_ids(agent) == [tech.id]

      agent = add_extra_teams(agent, [sales])
      assert Accounts.team_ids(agent) == [tech.id, sales.id]
    end

    test "the primary team is never stored as an extra team", ctx do
      agent = add_extra_teams(ctx.agent, [ctx.tech, ctx.sales])

      assert Enum.map(agent.extra_teams, & &1.id) == [ctx.sales.id]
    end

    test "accepts string ids and blanks from the admin form", ctx do
      {:ok, agent} =
        Accounts.update_user(ctx.agent, %{"extra_team_ids" => ["", to_string(ctx.ops.id)]})

      assert Enum.map(agent.extra_teams, & &1.id) == [ctx.ops.id]

      {:ok, agent} = Accounts.update_user(agent, %{"extra_team_ids" => [""]})
      assert agent.extra_teams == []
    end

    test "updates without extra_team_ids keep the memberships", ctx do
      agent = add_extra_teams(ctx.agent, [ctx.sales])
      {:ok, _} = Accounts.update_user(agent, %{name: "Renamed"})

      assert Accounts.team_ids(agent) == [ctx.tech.id, ctx.sales.id]
    end

    test "create_user/1 accepts extra teams", ctx do
      {:ok, user} =
        Accounts.create_user(%{
          email: "new@example.com",
          hashed_password: "h",
          role: "team_member",
          team_id: ctx.tech.id,
          extra_team_ids: [ctx.ops.id]
        })

      assert Accounts.team_ids(user) == [ctx.tech.id, ctx.ops.id]
    end

    test "extra teams grant team access", ctx do
      refute Accounts.can_access_team?(ctx.agent, ctx.ops.id)

      agent = add_extra_teams(ctx.agent, [ctx.ops])
      assert Accounts.can_access_team?(agent, ctx.ops.id)
    end

    test "member counts include extra members", ctx do
      assert Accounts.count_team_members(ctx.ops.id) == 0
      refute Map.has_key?(Accounts.count_users_by_team(), ctx.ops.id)

      add_extra_teams(ctx.agent, [ctx.ops])

      assert Accounts.count_team_members(ctx.ops.id) == 1
      assert Accounts.count_users_by_team()[ctx.ops.id] == 1
      assert Accounts.count_users_by_team()[ctx.tech.id] == 1
    end

    test "list_users_by_team/1 includes extra members", ctx do
      refute ctx.agent.id in Enum.map(Accounts.list_users_by_team(ctx.ops.id), & &1.id)

      add_extra_teams(ctx.agent, [ctx.ops])
      assert ctx.agent.id in Enum.map(Accounts.list_users_by_team(ctx.ops.id), & &1.id)
    end
  end

  describe "boards" do
    test "include boards of extra teams", ctx do
      board_id = "#{min(ctx.sales.id, ctx.ops.id)}_#{max(ctx.sales.id, ctx.ops.id)}"

      assert Kanbans.list_boards_by_teams(Accounts.team_ids(ctx.agent)) == []

      agent = add_extra_teams(ctx.agent, [ctx.ops])
      assert [board] = Kanbans.list_boards_by_teams(Accounts.team_ids(agent))
      assert board.id == board_id
      assert board.team_id == ctx.ops.id
    end

    test "a pair shared by two of the user's teams is listed once", ctx do
      agent = add_extra_teams(ctx.agent, [ctx.sales, ctx.ops])

      assert [board] = Kanbans.list_boards_by_teams(Accounts.team_ids(agent))
      # Sales is the agent's first team in the pair, so the board faces Sales
      assert board.team_id == ctx.sales.id
    end

    test "get_board!/2 loads the pair's requests even for a viewer outside the pair", ctx do
      board_id = "#{min(ctx.sales.id, ctx.ops.id)}_#{max(ctx.sales.id, ctx.ops.id)}"

      board = Kanbans.get_board!(board_id, [ctx.tech.id])
      card_ids = Enum.flat_map(board.columns, fn c -> Enum.map(c.cards, & &1.id) end)

      assert card_ids == [ctx.request.id]
    end
  end

  describe "MCP request visibility" do
    test "requests of extra teams are visible", ctx do
      assert Tools.call("get_request", %{"id" => ctx.request.id}, ctx.agent) ==
               {:error, :not_found}

      agent = add_extra_teams(ctx.agent, [ctx.ops])
      assert {:ok, %{id: id}} = Tools.call("get_request", %{"id" => ctx.request.id}, agent)
      assert id == ctx.request.id

      assert {:ok, %{requests: [%{id: ^id}]}} = Tools.call("list_requests", %{}, agent)
    end
  end
end
