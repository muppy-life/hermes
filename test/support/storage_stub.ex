defmodule Hermes.Storage.Stub do
  @moduledoc """
  In-memory storage stub for tests. Records all calls so tests can assert on them.

  ## Usage in tests

      # Assert an upload happened
      assert Hermes.Storage.Stub.uploaded?("some/key")

      # Get all uploads
      Hermes.Storage.Stub.uploads()

      # Simulate a storage failure for the next call
      Hermes.Storage.Stub.fail_next(:upload)

      # Reset between tests (called in DataCase setup)
      Hermes.Storage.Stub.reset()
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{uploads: [], deletes: [], fail_next: []} end, name: __MODULE__)
  end

  def upload(key, _binary, _content_type) do
    if pop_fail(:upload) do
      {:error, :simulated_failure}
    else
      Agent.update(__MODULE__, fn state ->
        Map.update!(state, :uploads, &[key | &1])
      end)

      {:ok, %{}}
    end
  end

  def delete(key) do
    if pop_fail(:delete) do
      {:error, :simulated_failure}
    else
      Agent.update(__MODULE__, fn state ->
        Map.update!(state, :deletes, &[key | &1])
      end)

      {:ok, %{}}
    end
  end

  def public_url(key), do: "/stub/#{key}"

  def uploads, do: Agent.get(__MODULE__, & &1.uploads)
  def deletes, do: Agent.get(__MODULE__, & &1.deletes)
  def uploaded?(key), do: key in uploads()
  def deleted?(key), do: key in deletes()

  def fail_next(op) when op in [:upload, :delete] do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :fail_next, &[op | &1])
    end)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{uploads: [], deletes: [], fail_next: []} end)
  end

  defp pop_fail(op) do
    Agent.get_and_update(__MODULE__, fn state ->
      if op in state.fail_next do
        {true, Map.update!(state, :fail_next, &List.delete(&1, op))}
      else
        {false, state}
      end
    end)
  end
end
