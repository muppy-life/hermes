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
  Fetches a task by id, or nil if it does not exist. Used by the LiveView so a
  concurrently-deleted task (stale row) does not crash the process.
  """
  def get_tech_ops_task(id) do
    case Repo.get(Task, id) do
      nil -> nil
      task -> Repo.preload(task, @task_preloads)
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  @doc """
  Creates a task. Free-typed `reporter_name` / `issue_origin_name` in `attrs`
  are resolved to canonical lookup ids (created if new) inside the same
  transaction as the insert, so a failed insert never leaves orphaned lookups.
  """
  def create_tech_ops_task(attrs \\ %{}) do
    write_task_txn(fn ->
      %Task{}
      |> Task.changeset(resolve_lookup_attrs(attrs))
      |> Repo.insert()
    end)
  end

  @doc """
  Updates a task, resolving lookups in the same transaction as the update. If
  the task was concurrently deleted the update raises `Ecto.StaleEntryError`,
  the transaction rolls back, and any lookups created for this edit are undone.
  """
  def update_tech_ops_task(%Task{} = task, attrs) do
    write_task_txn(fn ->
      task
      |> Task.changeset(resolve_lookup_attrs(attrs))
      |> Repo.update()
    end)
  end

  # Runs `fun` (which returns {:ok, task} | {:error, changeset}) in a
  # transaction, unwrapping the result and rolling back on error so lookup
  # inserts performed inside `fun` are reverted together with the task write.
  defp write_task_txn(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, task} -> task
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Resolve free-typed reporter / issue-origin names in the attrs to lookup ids.
  # Accepts string or atom keys; leaves attrs untouched when the name keys are
  # absent (e.g. API callers that pass ids directly).
  defp resolve_lookup_attrs(attrs) do
    {reporter_name, attrs} = pop_attr(attrs, "reporter_name", :reporter_name)
    {origin_name, attrs} = pop_attr(attrs, "issue_origin_name", :issue_origin_name)

    attrs
    |> maybe_put_lookup_id("reporter_id", reporter_name, &resolve_lookup_row(Reporter, &1))
    |> maybe_put_lookup_id("issue_origin_id", origin_name, &resolve_lookup_row(IssueOrigin, &1))
  end

  defp pop_attr(attrs, string_key, atom_key) do
    cond do
      Map.has_key?(attrs, string_key) -> Map.pop(attrs, string_key)
      Map.has_key?(attrs, atom_key) -> Map.pop(attrs, atom_key)
      true -> {:__absent__, attrs}
    end
  end

  defp maybe_put_lookup_id(attrs, _id_key, :__absent__, _resolver), do: attrs

  defp maybe_put_lookup_id(attrs, id_key, name, resolver) do
    Map.put(attrs, id_key, resolver.(name) |> then(fn row -> row && row.id end))
  end

  # Resolve within the surrounding transaction (raises on unexpected failure so
  # the transaction rolls back).
  defp resolve_lookup_row(schema, name) do
    case resolve_or_create(schema, name) do
      {:ok, row} -> row
    end
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
