defmodule Hermes.Workers.ExampleWorker do
  @moduledoc """
  Example Oban worker for heavy computing jobs.

  This worker demonstrates how to:
  - Process jobs asynchronously
  - Handle retries
  - Set priority and queue
  - Schedule jobs for later execution

  ## Usage

  Enqueue a job to run immediately:

      %{id: 1, operation: "process"}
      |> Hermes.Workers.ExampleWorker.new()
      |> Oban.insert()

  Enqueue a job to run in 5 minutes:

      %{id: 1, operation: "process"}
      |> Hermes.Workers.ExampleWorker.new(schedule_in: 300)
      |> Oban.insert()

  Enqueue with custom queue and priority:

      %{id: 1, operation: "process"}
      |> Hermes.Workers.ExampleWorker.new(queue: :media, priority: 1)
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    priority: 0

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id, "operation" => operation}}) do
    Logger.info("Starting job for id: #{id}, operation: #{operation}")

    # Simulate heavy computation
    result = do_heavy_computation(id, operation)

    Logger.info("Completed job for id: #{id}, result: #{inspect(result)}")

    :ok
  end

  defp do_heavy_computation(id, operation) do
    # Simulate some heavy work
    :timer.sleep(1000)

    case operation do
      "process" ->
        {:ok, "Processed item #{id}"}

      "analyze" ->
        {:ok, "Analyzed item #{id}"}

      _ ->
        {:error, "Unknown operation: #{operation}"}
    end
  end
end
