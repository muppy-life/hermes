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
end
