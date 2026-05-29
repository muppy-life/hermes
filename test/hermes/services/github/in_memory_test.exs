defmodule Hermes.Services.GitHub.InMemoryTest do
  use ExUnit.Case, async: false

  alias Hermes.Services.GitHub.InMemory

  setup do
    case Process.whereis(InMemory) do
      nil -> {:ok, _} = InMemory.start_link([])
      _pid -> InMemory.reset()
    end

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

  test "set_state dev helper" do
    {:ok, %{number: n}} =
      InMemory.create_issue(%{owner: "a", repo: "r", title: "t", body: "b", labels: []})

    InMemory.set_state("a", "r", n, "closed")
    assert %{state: "closed"} = InMemory.get("a", "r", n)
  end
end
