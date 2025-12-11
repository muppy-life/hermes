defmodule Hermes.Requests do
  @moduledoc """
  The Requests context for managing team requests.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo
  alias Hermes.Requests.DraftStore
  alias Hermes.Requests.Request
  alias Hermes.Requests.RequestChange
  alias Hermes.Requests.RequestComment

  def list_requests do
    Request
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def list_requests_by_team(team_id) do
    from(r in Request,
      where: r.requesting_team_id == ^team_id or r.assigned_to_team_id == ^team_id,
      order_by: [desc: r.updated_at]
    )
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def list_pending_requests do
    from(r in Request,
      where: r.status == "pending",
      order_by: [desc: r.priority, desc: r.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def get_request!(id) do
    Repo.get!(Request, id)
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def create_request(attrs \\ %{}, user_id \\ nil) do
    # Generate fallback title from first 10 words of goal if title is missing
    # This ensures request always has a title even if ML model never completes
    attrs_with_title = ensure_title(attrs)

    result =
      %Request{}
      |> Request.changeset(attrs_with_title)
      |> Repo.insert()

    case result do
      {:ok, request} ->
        log_change(request.id, user_id, "created", %{changes: attrs_with_title})

        # Trigger async title generation from goal description
        # This will update the title with AI-generated summary when model is ready
        trigger_title_summarization(request)

        # Trigger async diagram generation from goal and expected output
        # This will create a visual representation of the solution flow
        trigger_diagram_generation(request)

        {:ok, request}

      error ->
        error
    end
  end

  defp ensure_title(attrs) do
    # If title is already provided and not empty, use it
    case Map.get(attrs, "title") || Map.get(attrs, :title) do
      nil -> generate_fallback_title(attrs)
      "" -> generate_fallback_title(attrs)
      _title -> attrs
    end
  end

  defp generate_fallback_title(attrs) do
    goal = Map.get(attrs, "goal_description") || Map.get(attrs, :goal_description) || ""

    # Take first 10 words from goal description
    fallback_title =
      goal
      |> String.split()
      |> Enum.take(10)
      |> Enum.join(" ")
      |> case do
        "" -> "New Request"
        title -> title
      end

    Map.put(attrs, "title", fallback_title)
  end

  defp trigger_title_summarization(request) do
    # Build text to summarize from request goal and context
    text_to_summarize = build_summarization_text(request)

    # Trigger async summarization job
    %{
      request_id: request.id,
      text: text_to_summarize,
      # Short title
      max_length: 60,
      min_length: 20,
      field_to_update: "title"
    }
    |> Hermes.Workers.SummarizationWorker.new(queue: :media)
    |> Oban.insert()
  end

  defp build_summarization_text(request) do
    # Use only user-provided text without English labels to preserve input language
    # The mT5 model will output in the same language as the input
    [
      request.goal_description,
      request.current_situation,
      request.expected_output
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  def trigger_diagram_generation(request) do
    # Only trigger if feature is enabled
    if diagram_generation_enabled?() do
      # Trigger async diagram generation job
      %{request_id: request.id}
      |> Hermes.Workers.DiagramGenerationWorker.new(queue: :default)
      |> Oban.insert()
    else
      {:ok, :feature_disabled}
    end
  end

  @doc """
  Triggers diagram generation for a request by ID.
  Used when viewing requests that don't have diagrams yet.
  """
  def trigger_diagram_generation_for_request(request_id) do
    # Only trigger if feature is enabled
    if diagram_generation_enabled?() do
      %{request_id: request_id}
      |> Hermes.Workers.DiagramGenerationWorker.new(queue: :default)
      |> Oban.insert()
    else
      {:ok, :feature_disabled}
    end
  end

  @doc """
  Checks if the solution diagram generation feature is enabled.
  """
  def diagram_generation_enabled? do
    Application.get_env(:hermes, :features, [])
    |> Keyword.get(:solution_diagram_generation, false)
  end

  def update_request(%Request{} = request, attrs, user_id \\ nil) do
    changeset = Request.changeset(request, attrs)
    changes = changeset.changes

    result = Repo.update(changeset)

    case result do
      {:ok, updated_request} ->
        if map_size(changes) > 0 do
          log_changes(updated_request.id, user_id, request, changes)
        end

        # Trigger diagram generation if solution_diagram is missing
        if is_nil(updated_request.solution_diagram) or updated_request.solution_diagram == "" do
          trigger_diagram_generation(updated_request)
        end

        {:ok, updated_request}

      error ->
        error
    end
  end

  def delete_request(%Request{} = request) do
    Repo.delete(request)
  end

  def change_request(%Request{} = request, attrs \\ %{}) do
    Request.changeset(request, attrs)
  end

  # Request change tracking functions

  def list_request_changes(request_id) do
    from(rc in RequestChange,
      where: rc.request_id == ^request_id,
      order_by: [desc: rc.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp log_change(request_id, user_id, action, attrs) do
    %RequestChange{}
    |> RequestChange.changeset(
      Map.merge(attrs, %{
        request_id: request_id,
        user_id: user_id,
        action: action
      })
    )
    |> Repo.insert()
  end

  defp log_changes(request_id, user_id, old_request, changes) do
    # Log each field change individually
    Enum.each(changes, fn {field, new_value} ->
      old_value = Map.get(old_request, field)

      log_change(request_id, user_id, "updated", %{
        field: to_string(field),
        old_value: format_value(old_value),
        new_value: format_value(new_value)
      })
    end)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_nil(value), do: nil
  defp format_value(value), do: inspect(value)

  # Request comment functions

  def list_request_comments(request_id) do
    from(rc in RequestComment,
      where: rc.request_id == ^request_id,
      order_by: [asc: rc.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def create_comment(attrs \\ %{}) do
    %RequestComment{}
    |> RequestComment.changeset(attrs)
    |> Repo.insert()
  end

  def delete_comment(%RequestComment{} = comment) do
    Repo.delete(comment)
  end

  # Draft functions for request creation form

  @doc """
  Get a draft for the given user ID.
  Returns nil if no draft exists.
  """
  def get_draft(user_id) do
    DraftStore.get(user_id)
  end

  @doc """
  Save a draft for the given user ID.
  """
  def save_draft(user_id, step, form_data) do
    DraftStore.save(user_id, step, form_data)
  end

  @doc """
  Delete a draft for the given user ID.
  """
  def delete_draft(user_id) do
    DraftStore.delete(user_id)
  end
end
