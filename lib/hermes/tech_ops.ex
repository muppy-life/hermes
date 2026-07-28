defmodule Hermes.TechOps do
  @moduledoc """
  The TechOps context: records tech ops tasks (issues handled by whoever holds
  the rotating tech ops role).

  Reporter and issue origin are managed lookup lists rather than free text, so
  values stay canonical (deduplicated on a normalized key) across the UI and,
  later, any API writers.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo

  alias Hermes.TechOps.IssueOrigin
  alias Hermes.TechOps.Reporter
  alias Hermes.TechOps.Task

  @task_preloads [:responsible, :team, :reporter, :issue_origin]

  def list_tech_ops_tasks do
    from(t in Task, order_by: [desc: t.recorded_on, desc: t.id])
    |> Repo.all()
    |> Repo.preload(@task_preloads)
  end

  def get_tech_ops_task!(id), do: Repo.get!(Task, id) |> Repo.preload(@task_preloads)

  @doc """
  Fetches a task by id, returning `nil` when it does not exist or the id is not
  a valid integer. Used by the LiveView (so a concurrently-deleted task does not
  crash the process) and by the API/MCP layer.
  """
  def get_tech_ops_task(id) do
    case Repo.get(Task, id) do
      nil -> nil
      task -> Repo.preload(task, @task_preloads)
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

  ## Reporters (lookup)

  def list_reporters do
    from(r in Reporter, order_by: [asc: r.name]) |> Repo.all()
  end

  @doc """
  Returns the canonical reporter matching `name` (by normalized key), creating
  it if none exists. Blank input returns `{:ok, nil}` (reporter is optional).
  Safe against races via the normalized unique index.
  """
  def resolve_or_create_reporter(name), do: resolve_or_create(Reporter, name)

  ## Issue origins (lookup)

  def list_issue_origins do
    from(o in IssueOrigin, order_by: [asc: o.name]) |> Repo.all()
  end

  @doc """
  Returns the canonical issue origin matching `name` (by normalized key),
  creating it if none exists. Blank input returns `{:ok, nil}`.
  """
  def resolve_or_create_issue_origin(name), do: resolve_or_create(IssueOrigin, name)

  # Shared resolve-or-create for the lookup schemas. Normalizes, looks up by the
  # unique normalized key, and inserts if missing. On a concurrent insert the
  # unique constraint fires and we re-read the winning row.
  defp resolve_or_create(schema, name) do
    key = schema.normalize(name)

    if key == "" do
      {:ok, nil}
    else
      case Repo.get_by(schema, normalized: key) do
        nil -> insert_lookup(schema, name, key)
        row -> {:ok, row}
      end
    end
  end

  defp insert_lookup(schema, name, key) do
    case struct(schema) |> schema.changeset(%{"name" => name}) |> Repo.insert() do
      {:ok, row} -> {:ok, row}
      # Lost an insert race: the row now exists, fetch the canonical one.
      {:error, _changeset} -> {:ok, Repo.get_by(schema, normalized: key)}
    end
  end
end
