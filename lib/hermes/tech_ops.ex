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
    |> Repo.preload(:responsible)
  end

  def get_tech_ops_task!(id), do: Repo.get!(Task, id) |> Repo.preload(:responsible)

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
