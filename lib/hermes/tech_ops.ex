defmodule Hermes.TechOps do
  @moduledoc """
  The TechOps context: records tech ops tasks (issues handled by whoever holds
  the rotating tech ops role).
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo

  alias Hermes.TechOps.Task

  def list_tech_ops_tasks do
    from(t in Task, order_by: [desc: t.recorded_on, desc: t.id])
    |> Repo.all()
    |> Repo.preload([:responsible, :team])
  end

  def get_tech_ops_task!(id), do: Repo.get!(Task, id) |> Repo.preload([:responsible, :team])

  @doc """
  Fetches a task by id, returning `nil` when it does not exist or the id is not
  a valid integer. Used by the LiveView (so a concurrently-deleted task does not
  crash the process) and by the API/MCP layer.
  """
  def get_tech_ops_task(id) do
    case Repo.get(Task, id) do
      nil -> nil
      task -> Repo.preload(task, [:responsible, :team])
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  def create_tech_ops_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_tech_ops_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_tech_ops_task(%Task{} = task) do
    Repo.delete(task)
  end
end
