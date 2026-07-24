defmodule Hermes.MCP.Tools do
  @moduledoc """
  Single source of truth for the tech-ops tools exposed over both the REST API
  and the MCP endpoint.

  Each tool has a JSON Schema `input_schema` (for MCP `tools/list`) and a
  handler `call/3` that runs the operation against `Hermes.TechOps`, attributing
  writes to the authenticated user. Handlers return `{:ok, map}` or
  `{:error, reason}` and are transport-agnostic; the REST and MCP controllers
  translate those into HTTP or JSON-RPC responses.
  """

  alias Hermes.Accounts.User
  alias Hermes.Requests
  alias Hermes.Requests.Request
  alias Hermes.TechOps
  alias Hermes.TechOps.Task

  @doc """
  Tool definitions for MCP `tools/list`. Order is stable for predictable
  client display.
  """
  def definitions do
    [
      %{
        name: "list_tech_ops_tasks",
        description:
          "List tech-ops tasks (engineering/operational issues), most recent first. " <>
            "Optionally filter by status.",
        input_schema: %{
          type: "object",
          properties: %{
            status: %{
              type: "string",
              enum: status_enum(),
              description: "Filter to tasks with this status."
            }
          },
          additionalProperties: false
        }
      },
      %{
        name: "get_tech_ops_task",
        description: "Fetch a single tech-ops task by id.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{type: "integer", description: "The tech-ops task id."}
          },
          required: ["id"],
          additionalProperties: false
        }
      },
      %{
        name: "report_tech_ops_task",
        description:
          "Report (create) a new tech-ops task. Use this when you discover or are " <>
            "asked to record an engineering/operational issue. You are set as the " <>
            "responsible person and the task starts in 'open' status.",
        input_schema: %{
          type: "object",
          properties: %{
            reported_problem: %{
              type: "string",
              description: "Description of the problem/issue being reported."
            },
            issue_origin: %{
              type: "string",
              description:
                "Where the issue came from (e.g. 'AppSignal alert', 'user report', 'deploy')."
            },
            recorded_on: %{
              type: "string",
              format: "date",
              description: "Date the issue was recorded (YYYY-MM-DD). Defaults to today."
            }
          },
          required: ["reported_problem"],
          additionalProperties: false
        }
      },
      %{
        name: "update_tech_ops_task",
        description:
          "Update a tech-ops task: change its status and/or add work notes. Set any " <>
            "subset of fields.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{type: "integer", description: "The tech-ops task id."},
            status: %{
              type: "string",
              enum: status_enum(),
              description: "New status."
            },
            resolution: %{
              type: "string",
              description: "Notes on what was done / how it was resolved."
            },
            issue_origin: %{type: "string", description: "Correct or set the issue origin."}
          },
          required: ["id"],
          additionalProperties: false
        }
      },
      %{
        name: "resolve_tech_ops_task",
        description:
          "Complete a tech-ops task: set its status to 'resolved' and record how it " <>
            "was resolved. Use this when the issue is fixed.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{type: "integer", description: "The tech-ops task id."},
            resolution: %{
              type: "string",
              description: "Summary of how the issue was resolved."
            }
          },
          required: ["id", "resolution"],
          additionalProperties: false
        }
      },
      %{
        name: "list_requests",
        description:
          "List team requests visible to you (those where your team is the requesting " <>
            "or assigned team), most recently updated first. Optionally filter by status.",
        input_schema: %{
          type: "object",
          properties: %{
            status: %{
              type: "string",
              description: "Filter to requests with this status."
            }
          },
          additionalProperties: false
        }
      },
      %{
        name: "get_request",
        description:
          "Fetch a single team request by id. Only requests visible to you (your team " <>
            "is the requesting or assigned team) can be fetched.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{type: "integer", description: "The request id."}
          },
          required: ["id"],
          additionalProperties: false
        }
      }
    ]
  end

  @doc "The set of tool names, for validation."
  def tool_names, do: Enum.map(definitions(), & &1.name)

  @doc """
  Runs a tool by name with string-keyed `args` on behalf of `user`.

  Returns `{:ok, result_map}` or `{:error, reason}` where reason is one of
  `:not_found`, `:unknown_tool`, `:unauthenticated`, `{:invalid, message}`, or
  a changeset.

  Every tool requires an authenticated `%User{}`. This is defense-in-depth: the
  `ApiAuth` plug already rejects unauthenticated callers, but guarding here
  ensures a tool can never run without a user even if a future route forgot to
  pipe through auth.
  """
  def call(_name, _args, user) when not is_struct(user, User), do: {:error, :unauthenticated}

  def call("list_tech_ops_tasks", args, _user) do
    tasks = TechOps.list_tech_ops_tasks()

    tasks =
      case Map.get(args, "status") do
        nil -> tasks
        "" -> tasks
        status -> Enum.filter(tasks, &(to_string(&1.status) == status))
      end

    {:ok, %{tasks: Enum.map(tasks, &serialize/1)}}
  end

  def call("get_tech_ops_task", %{"id" => id}, _user) do
    with {:ok, task} <- fetch_task(id) do
      {:ok, serialize(task)}
    end
  end

  def call("report_tech_ops_task", args, %User{} = user) do
    attrs =
      %{
        "reported_problem" => Map.get(args, "reported_problem"),
        "issue_origin" => Map.get(args, "issue_origin"),
        "recorded_on" => Map.get(args, "recorded_on") || Date.utc_today(),
        "status" => "open",
        "responsible_id" => user.id
      }

    case TechOps.create_tech_ops_task(attrs) do
      {:ok, task} -> {:ok, serialize(TechOps.get_tech_ops_task(task.id))}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def call("update_tech_ops_task", %{"id" => id} = args, _user) do
    attrs =
      args
      |> Map.take(["status", "resolution", "issue_origin"])
      |> reject_nil()

    with {:ok, task} <- fetch_task(id),
         {:ok, task} <- TechOps.update_tech_ops_task(task, attrs) do
      {:ok, serialize(task)}
    end
  end

  def call("resolve_tech_ops_task", %{"id" => id} = args, _user) do
    attrs = %{"status" => "resolved", "resolution" => Map.get(args, "resolution")}

    with {:ok, task} <- fetch_task(id),
         {:ok, task} <- TechOps.update_tech_ops_task(task, attrs) do
      {:ok, serialize(task)}
    end
  end

  def call("list_requests", args, %User{} = user) do
    requests = Requests.list_requests_by_team(user.team_id)

    requests =
      case Map.get(args, "status") do
        nil -> requests
        "" -> requests
        status -> Enum.filter(requests, &(&1.status == status))
      end

    {:ok, %{requests: Enum.map(requests, &serialize_request/1)}}
  end

  def call("get_request", %{"id" => id}, %User{} = user) do
    with {:ok, request} <- fetch_visible_request(id, user) do
      {:ok, serialize_request(request)}
    end
  end

  def call(name, _args, _user) when is_binary(name) do
    if name in tool_names() do
      {:error, {:invalid, "Missing required arguments for #{name}"}}
    else
      {:error, :unknown_tool}
    end
  end

  @doc "Serializes a task to a plain, JSON-safe map for API/MCP responses."
  def serialize(%Task{} = task) do
    %{
      id: task.id,
      reported_problem: task.reported_problem,
      issue_origin: task.issue_origin,
      status: to_string(task.status),
      status_label: Task.status_label(task.status),
      resolution: task.resolution,
      recorded_on: task.recorded_on,
      responsible: serialize_user(task.responsible),
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp serialize_user(%User{} = user),
    do: %{id: user.id, name: User.display_name(user), email: user.email}

  defp serialize_user(_), do: nil

  @doc "Serializes a request to a plain, JSON-safe map for the read API/MCP."
  def serialize_request(%Request{} = request) do
    %{
      id: request.id,
      title: request.title,
      description: request.description,
      status: request.status,
      priority: request.priority,
      priority_label: Request.priority_label(request.priority),
      kind: request.kind,
      deadline: request.deadline,
      is_epic: request.is_epic,
      requesting_team: serialize_team(request.requesting_team),
      assigned_to_team: serialize_team(request.assigned_to_team),
      created_by: serialize_user(request.created_by),
      inserted_at: request.inserted_at,
      updated_at: request.updated_at
    }
  end

  defp serialize_team(%{id: id, name: name}), do: %{id: id, name: name}
  defp serialize_team(_), do: nil

  # Fetches a request only if the user's team is its requesting or assigned team.
  # Anything outside that scope is reported as :not_found so the API never
  # reveals the existence of requests the user could not otherwise see.
  defp fetch_visible_request(id, %User{team_id: team_id}) do
    case parse_id(id) do
      :error ->
        {:error, {:invalid, "id must be an integer"}}

      {:ok, int} ->
        case Requests.get_request(int) do
          %Request{requesting_team_id: ^team_id} = request -> {:ok, request}
          %Request{assigned_to_team_id: ^team_id} = request -> {:ok, request}
          _ -> {:error, :not_found}
        end
    end
  end

  defp fetch_task(id) do
    case parse_id(id) do
      {:ok, int} ->
        case TechOps.get_tech_ops_task(int) do
          nil -> {:error, :not_found}
          task -> {:ok, task}
        end

      :error ->
        {:error, {:invalid, "id must be an integer"}}
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp reject_nil(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp status_enum, do: Enum.map(Task.statuses(), &to_string/1)
end
