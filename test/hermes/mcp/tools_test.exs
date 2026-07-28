defmodule Hermes.MCP.ToolsTest do
  use Hermes.DataCase

  alias Hermes.MCP.Tools

  describe "call/3 authentication guard" do
    test "every tool rejects a nil user with :unauthenticated" do
      for name <- Tools.tool_names() do
        assert Tools.call(name, %{}, nil) == {:error, :unauthenticated},
               "expected #{name} to reject a nil user"
      end
    end

    test "rejects a non-User struct" do
      assert Tools.call("list_tech_ops_tasks", %{}, %{id: 1}) == {:error, :unauthenticated}
    end

    test "an unknown tool with a nil user is still unauthenticated (auth checked first)" do
      assert Tools.call("does_not_exist", %{}, nil) == {:error, :unauthenticated}
    end
  end

  describe "concurrent deletion during a write" do
    setup do
      {:ok, team} = Hermes.Accounts.create_team(%{name: "Platform", description: "d"})

      {:ok, user} =
        Hermes.Accounts.create_user(%{
          email: "race@example.com",
          hashed_password: :crypto.hash(:sha256, "x") |> Base.encode16(case: :lower),
          role: "dev_team",
          team_id: team.id
        })

      %{user: user}
    end

    # Preloading the struct in hand (rather than re-fetching by id) keeps the
    # response complete even once the task's own row is gone.
    test "associations still serialize after the task row is deleted", %{user: user} do
      {:ok, _} = Hermes.TechOps.resolve_or_create_reporter("Alejandra")

      {:ok, task} =
        Hermes.TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x",
          "reporter_name" => "Alejandra",
          "responsible_id" => user.id
        })

      Hermes.TechOps.delete_tech_ops_task(task)

      payload = Tools.serialize(Hermes.TechOps.preload_task(task))

      assert payload.id == task.id
      assert payload.reporter.name == "Alejandra"
      assert payload.responsible.email == "race@example.com"
    end

    test "resolve reports an already-deleted task as not found", %{user: user} do
      {:ok, task} =
        Hermes.TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x"
        })

      Hermes.TechOps.delete_tech_ops_task(task)

      assert Tools.call("resolve_tech_ops_task", %{"id" => task.id, "resolution" => "x"}, user) ==
               {:error, :not_found}
    end
  end

  describe "lookup value types" do
    setup do
      {:ok, team} = Hermes.Accounts.create_team(%{name: "Platform", description: "d"})

      {:ok, user} =
        Hermes.Accounts.create_user(%{
          email: "dev@example.com",
          hashed_password: :crypto.hash(:sha256, "x") |> Base.encode16(case: :lower),
          role: "dev_team",
          team_id: team.id
        })

      %{user: user}
    end

    # A malformed JSON value must be a controlled error, not a raised
    # FunctionClauseError from the name-normalizing helpers.
    for {label, value} <- [{"an integer", 7}, {"a list", ["a"]}, {"an object", %{"a" => 1}}] do
      test "rejects #{label} for team without raising", %{user: user} do
        args = %{"reported_problem" => "x", "team" => unquote(Macro.escape(value))}

        assert {:error, {:invalid, message}} =
                 Tools.call("report_tech_ops_task", args, user)

        assert message =~ "team must be a string"
      end

      test "rejects #{label} for responsible without raising", %{user: user} do
        args = %{"reported_problem" => "x", "responsible" => unquote(Macro.escape(value))}

        assert {:error, {:invalid, message}} =
                 Tools.call("report_tech_ops_task", args, user)

        assert message =~ "responsible must be a string"
      end
    end
  end
end
