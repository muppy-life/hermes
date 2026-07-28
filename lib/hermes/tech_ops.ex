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

  @doc "Finds a reporter by normalized name, or nil. Does not create."
  def find_reporter(name), do: find_lookup(Reporter, name)

  @doc "Explicitly creates a canonical reporter (normalized upsert semantics)."
  def create_reporter(name), do: create_lookup(Reporter, name)

  @doc "Reporters whose name is close to `name` (for 'did you mean' suggestions)."
  def suggest_reporters(name, limit \\ 5), do: suggest_lookup(Reporter, name, limit)

  ## Issue origins (lookup)

  def list_issue_origins do
    from(o in IssueOrigin, order_by: [asc: o.name]) |> Repo.all()
  end

  @doc """
  Returns the canonical issue origin matching `name` (by normalized key),
  creating it if none exists. Blank input returns `{:ok, nil}`.
  """
  def resolve_or_create_issue_origin(name), do: resolve_or_create(IssueOrigin, name)

  @doc "Finds an issue origin by normalized name, or nil. Does not create."
  def find_issue_origin(name), do: find_lookup(IssueOrigin, name)

  @doc "Explicitly creates a canonical issue origin (normalized upsert semantics)."
  def create_issue_origin(name), do: create_lookup(IssueOrigin, name)

  @doc "Issue origins whose name is close to `name` (for suggestions)."
  def suggest_issue_origins(name, limit \\ 5), do: suggest_lookup(IssueOrigin, name, limit)

  # Look up an existing lookup row by normalized key; nil for blank/unknown.
  defp find_lookup(schema, name) do
    case schema.normalize(name) do
      "" -> nil
      key -> Repo.get_by(schema, normalized: key)
    end
  end

  # Explicit create: returns {:ok, row} for a new or existing (idempotent)
  # value, or {:error, changeset} for a blank name. Race-safe via the unique
  # normalized index.
  defp create_lookup(schema, name) do
    case schema.normalize(name) do
      "" ->
        # Surface a real validation error for a blank name rather than a
        # silent no-op.
        {:error, struct(schema) |> schema.changeset(%{"name" => name})}

      key ->
        case Repo.get_by(schema, normalized: key) do
          nil -> insert_lookup(schema, name, key)
          row -> {:ok, row}
        end
    end
  end

  # Suggestions: rows whose normalized key contains the (normalized) query as a
  # substring. Empty query yields no suggestions.
  defp suggest_lookup(schema, name, limit) do
    case schema.normalize(name) do
      "" ->
        []

      key ->
        pattern = "%#{escape_like(key)}%"

        from(r in schema,
          where: like(r.normalized, ^pattern),
          order_by: [asc: r.name],
          limit: ^limit
        )
        |> Repo.all()
    end
  end

  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

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
