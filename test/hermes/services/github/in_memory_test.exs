defmodule Hermes.Services.GitHub.InMemoryTest do
  use ExUnit.Case, async: false

  alias Hermes.Services.GitHub.InMemory

  setup do
    # A leftover instance from another file is linked to its (now exiting)
    # test process and can die between whereis/1 and the first call. Kill it
    # synchronously and start a fresh supervised instance per test.
    if pid = Process.whereis(InMemory) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end

    start_supervised!(InMemory)
    :ok
  end

  test "create_issue autoincrements numbers per repo" do
    payload = %{
      owner: "acme",
      repo: "main",
      title: "first",
      body: "body",
      labels: []
    }

    assert {:ok, %{number: 1, url: url1}} = InMemory.create_issue(payload)
    assert {:ok, %{number: 2, url: url2}} = InMemory.create_issue(%{payload | title: "second"})

    refute url1 == url2

    assert {:ok, %{number: 1}} =
             InMemory.create_issue(%{payload | repo: "other"})
  end

  test "update_issue mutates stored fields" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    assert {:ok, updated} =
             InMemory.update_issue(%{
               owner: "a",
               repo: "r",
               number: n,
               title: "new",
               body: "new body",
               labels: ["x"]
             })

    assert updated.title == "new"
    assert updated.body == "new body"
    assert updated.labels == ["x"]
  end

  test "set_issue_state toggles state" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    assert {:ok, %{state: "closed"}} =
             InMemory.set_issue_state(%{owner: "a", repo: "r", number: n}, :closed)

    assert {:ok, %{state: "closed"}} = InMemory.get_issue("a", "r", n)
  end

  test "get_issue returns 404 for unknown" do
    assert {:error, {:http_error, 404, _}} = InMemory.get_issue("nope", "nope", 99)
  end

  test "create_comment appends to issue, errors when issue missing" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    assert {:ok, _} =
             InMemory.create_comment(%{owner: "a", repo: "r", number: n}, "hello")

    assert [%{body: "hello"}] = InMemory.comments_for("a", "r", n)

    assert {:error, {:http_error, 404, _}} =
             InMemory.create_comment(%{owner: "a", repo: "r", number: 999}, "ghost")
  end

  test "delete_comment removes the comment by id" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    {:ok, %{id: id}} = InMemory.create_comment(%{owner: "a", repo: "r", number: n}, "hello")

    assert {:ok, _} = InMemory.delete_comment(%{owner: "a", repo: "r", number: n}, id)
    assert [] = InMemory.comments_for("a", "r", n)
  end

  test "list_sub_issues returns attached children with metadata" do
    {:ok, %{number: pn}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "parent", body: "b", labels: []})

    {:ok, %{number: cn}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "child", body: "b", labels: []})

    {:ok, parent_node} = InMemory.get_issue_node_id("a", "r", pn)
    {:ok, child_node} = InMemory.get_issue_node_id("a", "r", cn)

    # No sub-issues attached yet.
    assert {:ok, []} = InMemory.list_sub_issues(parent_node)

    {:ok, _} = InMemory.add_sub_issue(parent_node, child_node)

    assert {:ok, [sub]} = InMemory.list_sub_issues(parent_node)
    assert sub.number == cn
    assert sub.title == "child"
    assert sub.state == "open"
    assert sub.owner == "a"
    assert sub.repo == "r"
    assert sub.node_id == child_node
  end

  test "set_state dev helper" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    InMemory.set_state("a", "r", n, "closed")
    assert %{state: "closed"} = InMemory.get("a", "r", n)
  end
end
