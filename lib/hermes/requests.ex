defmodule Hermes.Requests do
  @moduledoc """
  The Requests context for managing team requests.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Hermes.Repo
  alias Hermes.Requests.DraftStore
  alias Hermes.Requests.GitHubIssue
  alias Hermes.Requests.GitHubStatusMapping
  alias Hermes.Requests.Request
  alias Hermes.Requests.RequestChange
  alias Hermes.Requests.RequestComment
  alias Hermes.Requests.RequestImage
  alias Hermes.Services.GitHub
  alias Hermes.Storage

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

        trigger_request_created_notification(request)

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
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
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

        trigger_github_sync_on_update(updated_request, request, changes)

        {:ok, updated_request}

      error ->
        error
    end
  end

  def delete_request(%Request{} = request) do
    images = list_request_images(request.id)

    Enum.each(images, fn image ->
      case Storage.delete(image.key) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete image #{image.key}: #{inspect(reason)}")
      end
    end)

    Repo.delete(request)
  end

  def change_request(%Request{} = request, attrs \\ %{}) do
    Request.changeset(request, attrs)
  end

  # Subtask functions

  def list_subtasks(parent_id) do
    from(r in Request,
      where: r.parent_id == ^parent_id,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def create_subtask(%Request{status: "discarded"}, _title, _user_id) do
    {:error, :parent_discarded}
  end

  def create_subtask(%Request{} = parent, title, user_id) do
    case insert_subtask(parent, %{title: title}, user_id) do
      {:ok, subtask} ->
        maybe_auto_sync_subtask(parent, subtask)

        # Re-fetch parent issue to also update its Epic label now that it has a subtask
        maybe_refresh_parent_epic_label(parent)

        {:ok, Repo.preload(subtask, [:requesting_team, :assigned_to_team, :created_by])}

      error ->
        error
    end
  end

  # Inserts a subtask row under `parent`, inheriting priority/teams, and logs
  # the change. Does not perform any GitHub sync — callers decide that.
  defp insert_subtask(%Request{} = parent, overrides, user_id) do
    attrs =
      Map.merge(
        %{
          title: nil,
          priority: parent.priority || 2,
          status: "new",
          requesting_team_id: parent.requesting_team_id,
          assigned_to_team_id: parent.assigned_to_team_id,
          created_by_id: user_id
        },
        overrides
      )

    result =
      %Request{}
      |> Request.changeset(attrs)
      |> Ecto.Changeset.put_change(:parent_id, parent.id)
      |> Repo.insert()

    with {:ok, subtask} <- result do
      log_change(subtask.id, user_id, "created", %{
        changes: Map.put(attrs, :parent_id, parent.id)
      })

      {:ok, subtask}
    end
  end

  @doc """
  Lists the parent issue's GitHub sub-issues that are not yet imported as
  Hermes subtasks. Returns `{:ok, []}` when the request is unlinked or has no
  remote sub-issues. Each entry carries `owner/repo/number/title/state/url`.
  """
  def list_linkable_github_subtasks(%Request{} = parent) do
    case get_github_issue(parent.id) do
      nil ->
        {:ok, []}

      %GitHubIssue{} = parent_issue ->
        with {:ok, subs} <- GitHub.list_sub_issues(parent_issue) do
          {:ok, Enum.reject(subs, &github_issue_already_imported?/1)}
        end
    end
  end

  defp github_issue_already_imported?(%{owner: owner, repo: repo, number: number}) do
    Repo.exists?(
      from(i in GitHubIssue,
        where: i.owner == ^owner and i.repo == ^repo and i.number == ^number
      )
    )
  end

  @doc """
  Imports the given GitHub sub-issues as Hermes subtasks of `parent`. For each
  entry a subtask row is created, the existing GitHub issue is recorded against
  it (no new issue is created), and the sub-issue relationship is ensured.

  Each `sub` is a map with `:owner, :repo, :number, :title, :state, :url`
  (as returned by `list_linkable_github_subtasks/1`). Closed issues yield a
  subtask with status `completed`.

  Returns `{:ok, %{imported: i, skipped: s, failed: f}}` so the caller can tell
  the user how many imports actually succeeded versus were already present or
  failed (each subtask import is atomic, so a failure leaves no partial row).
  """
  def import_github_subtasks(%Request{} = parent, subs, user_id) when is_list(subs) do
    case get_github_issue(parent.id) do
      nil ->
        {:error, :parent_not_linked}

      %GitHubIssue{} = parent_issue ->
        tally =
          subs
          |> Enum.map(&import_github_subtask(parent, parent_issue, &1, user_id))
          |> Enum.frequencies()

        maybe_refresh_parent_epic_label(parent)

        {:ok,
         %{
           imported: Map.get(tally, :ok, 0),
           skipped: Map.get(tally, :skip, 0),
           failed: Map.get(tally, :error, 0)
         }}
    end
  end

  defp import_github_subtask(%Request{} = parent, %GitHubIssue{} = parent_issue, sub, user_id) do
    if github_issue_already_imported?(sub) do
      :skip
    else
      status = if sub.state == "closed", do: "completed", else: "new"

      # The subtask row and its GitHub link must persist together — otherwise a
      # failed link insert (e.g. a unique-constraint clash from a concurrent
      # import) would leave an orphaned subtask diverging from GitHub. The
      # GitHub API calls run only after the DB writes commit.
      txn =
        Repo.transaction(fn ->
          with {:ok, subtask} <-
                 insert_subtask(
                   parent,
                   %{title: subtask_title(sub.title), status: status},
                   user_id
                 ),
               {:ok, child_issue} <-
                 insert_github_issue(subtask.id, %{
                   owner: sub.owner,
                   repo: sub.repo,
                   number: sub.number,
                   url: sub.url,
                   state: sub.state
                 }) do
            {subtask, child_issue}
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      case txn do
        {:ok, {subtask, child_issue}} ->
          attach_sub_issue(parent_issue, child_issue)
          maybe_prefix_issue_title(child_issue, subtask)
          :ok

        {:error, reason} ->
          Logger.warning(
            "import_github_subtask failed parent_id=#{parent.id} issue=#{sub.owner}/#{sub.repo}##{sub.number} reason=#{inspect(reason)}"
          )

          :error
      end
    end
  end

  # Strips a leading `[Hermes #N]` marker so re-imported titles stay clean.
  defp subtask_title(title) when is_binary(title) do
    title
    |> String.replace(~r/^\[Hermes #\d+\]\s*/, "")
    |> String.trim()
  end

  defp subtask_title(_), do: "GitHub issue"

  # A freshly-created Hermes subtask must NOT spawn a new GitHub issue under a
  # linked parent — that would diverge from the parent's existing GitHub
  # sub-issues. We only ensure the sub-issue relationship when the subtask
  # already has a GitHub issue (e.g. imported). Pushing a Hermes-only subtask to
  # GitHub stays an explicit action.
  defp maybe_auto_sync_subtask(%Request{} = parent, %Request{} = subtask) do
    case get_github_issue(parent.id) do
      nil ->
        :ok

      %GitHubIssue{} = parent_issue ->
        sync_subtask_to_github_parent(subtask, parent_issue, create: false)
    end
  end

  defp maybe_refresh_parent_epic_label(%Request{} = parent) do
    case get_github_issue(parent.id) do
      nil ->
        :ok

      %GitHubIssue{} = issue ->
        # Re-issue an update so labels (including new Epic label) sync
        GitHub.update_issue(issue, annotate_epic(parent))
        :ok
    end
  end

  defp annotate_epic(%Request{id: id, parent_id: nil} = request) when not is_nil(id) do
    %{request | is_epic: has_active_subtasks?(id)}
  end

  defp annotate_epic(request), do: request

  defp has_active_subtasks?(parent_id) do
    Repo.exists?(from r in Request, where: r.parent_id == ^parent_id and r.status != "discarded")
  end

  def toggle_subtask_status(%Request{} = subtask, user_id) do
    new_status = if subtask.status == "completed", do: "new", else: "completed"
    update_request(subtask, %{status: new_status}, user_id)
  end

  # Discard / restore

  @discard_categories [
    :duplicate,
    :out_of_scope,
    :not_technically_viable,
    :replaced_by_another,
    :postponed_indefinitely,
    :not_a_priority,
    :no_resources_available,
    :no_longer_applicable,
    :other
  ]

  def discard_categories, do: @discard_categories

  def discard_request(%Request{status: "completed"}, _attrs, _user_id) do
    {:error, :already_completed}
  end

  def discard_request(%Request{status: "discarded"}, _attrs, _user_id) do
    {:error, :already_discarded}
  end

  def discard_request(%Request{} = request, %{category: category, reason: reason}, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      Repo.transaction(fn ->
        case discard_one(request, category, reason, user_id, now) do
          {:ok, updated} ->
            affected = [
              updated | cascade_discard_subtasks(updated, category, reason, user_id, now)
            ]

            {updated, affected}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {updated, affected}} ->
        Enum.each(affected, &close_github_as_not_planned(&1, category, reason))
        {:ok, updated}

      err ->
        err
    end
  end

  defp discard_one(request, category, reason, user_id, now) do
    old_request = request

    changeset =
      request
      |> Request.changeset(%{
        status: "discarded",
        discard_reason_category: category,
        discard_reason: reason
      })
      |> Ecto.Changeset.put_change(:discarded_by_id, user_id)
      |> Ecto.Changeset.put_change(:discarded_at, now)
      |> Ecto.Changeset.put_change(:pre_discard_status, request.status)

    case Repo.update(changeset) do
      {:ok, updated} ->
        if map_size(changeset.changes) > 0 do
          log_changes(updated.id, user_id, old_request, changeset.changes)
        end

        {:ok, updated}

      err ->
        err
    end
  end

  defp cascade_discard_subtasks(parent, category, reason, user_id, now) do
    parent.id
    |> list_subtasks()
    |> Enum.flat_map(fn sub ->
      if sub.status not in ["discarded", "completed"] do
        case discard_one(sub, category, reason, user_id, now) do
          {:ok, updated} -> [updated]
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        []
      end
    end)
  end

  def restore_request(%Request{status: status}, _user_id) when status != "discarded" do
    {:error, :not_discarded}
  end

  def restore_request(%Request{} = request, user_id) do
    if orphan_subtask?(request) do
      {:error, :parent_discarded}
    else
      result =
        Repo.transaction(fn ->
          case restore_one(request, user_id) do
            {:ok, updated} ->
              affected = [updated | cascade_restore_subtasks(updated, user_id)]
              {updated, affected}

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, {updated, affected}} ->
          Enum.each(affected, &reopen_github_issue/1)
          {:ok, updated}

        err ->
          err
      end
    end
  end

  defp restore_one(request, user_id) do
    old_request = request
    target_status = request.pre_discard_status || "new"

    changeset =
      request
      |> Request.changeset(%{
        status: target_status,
        discard_reason_category: nil,
        discard_reason: nil
      })
      |> Ecto.Changeset.put_change(:discarded_by_id, nil)
      |> Ecto.Changeset.put_change(:discarded_at, nil)
      |> Ecto.Changeset.put_change(:pre_discard_status, nil)

    case Repo.update(changeset) do
      {:ok, updated} ->
        if map_size(changeset.changes) > 0 do
          log_changes(updated.id, user_id, old_request, changeset.changes)
        end

        {:ok, updated}

      err ->
        err
    end
  end

  defp orphan_subtask?(%Request{parent_id: nil}), do: false

  defp orphan_subtask?(%Request{parent_id: parent_id}) do
    case Repo.get(Request, parent_id) do
      %Request{status: "discarded"} -> true
      _ -> false
    end
  end

  defp cascade_restore_subtasks(parent, user_id) do
    parent.id
    |> list_subtasks()
    |> Enum.flat_map(fn sub ->
      if sub.status == "discarded" do
        case restore_one(sub, user_id) do
          {:ok, updated} -> [updated]
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        []
      end
    end)
  end

  defp close_github_as_not_planned(%Request{} = request, category, reason) do
    if github_integration_enabled?() do
      case get_github_issue(request.id) do
        nil ->
          :ok

        %GitHubIssue{} = issue ->
          GitHub.set_issue_state(issue, :closed, reason: :not_planned)
          maybe_post_discard_comment(issue, category, reason)
          detach_from_project(issue)
          :ok
      end
    else
      :ok
    end
  end

  defp detach_from_project(%GitHubIssue{project_item_id: nil}), do: :ok

  defp detach_from_project(%GitHubIssue{project_item_id: item_id} = issue) do
    case GitHub.remove_item(item_id) do
      {:ok, _} ->
        issue
        |> GitHubIssue.changeset(%{project_item_id: nil, project_status: nil})
        |> Repo.update()

      {:error, reason} ->
        Logger.warning(
          "detach_from_project failed issue=#{issue.owner}/#{issue.repo}##{issue.number} item=#{item_id} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp maybe_post_discard_comment(%GitHubIssue{} = issue, category, reason) do
    body = """
    🗄️ **Discarded in Hermes**

    **Category:** #{format_discard_category(category)}

    **Justification:**
    #{reason}
    """

    case GitHub.create_comment(issue, body) do
      {:ok, _} ->
        :ok

      {:error, err} ->
        Logger.warning(
          "discard comment failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(err)}"
        )

        :ok
    end
  end

  defp format_discard_category(nil), do: "—"

  defp format_discard_category(c) when is_atom(c),
    do: c |> Atom.to_string() |> humanize_category()

  defp format_discard_category(c) when is_binary(c), do: humanize_category(c)

  defp humanize_category(c) do
    c |> String.replace("_", " ") |> String.capitalize()
  end

  defp reopen_github_issue(%Request{} = request) do
    if github_integration_enabled?() do
      case get_github_issue(request.id) do
        nil ->
          :ok

        %GitHubIssue{} = issue ->
          GitHub.set_issue_state(issue, :open)
          maybe_add_to_project(issue)
          :ok
      end
    else
      :ok
    end
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

  @doc """
  Completion timestamps for the given request ids, derived from the change log.

  Returns a map of `request_id => inserted_at` for the most recent transition
  whose status changed to `"completed"`. Requests with no such logged
  transition (e.g. seeded or completed before status changes were tracked) are
  absent from the map.
  """
  def completed_at_by_request(request_ids) do
    from(rc in RequestChange,
      where:
        rc.request_id in ^request_ids and rc.field == "status" and rc.new_value == "completed",
      group_by: rc.request_id,
      select: {rc.request_id, max(rc.inserted_at)}
    )
    |> Repo.all()
    |> Map.new()
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
    result =
      %RequestComment{}
      |> RequestComment.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, comment} ->
        mentioned_users = resolve_mentions(comment.content)
        trigger_comment_notification(comment)
        trigger_mention_notifications(comment, mentioned_users)
        trigger_github_comment_sync(comment)

        {:ok, comment}

      error ->
        error
    end
  end

  @doc """
  Parses @username mentions from comment content and returns the matching users.
  Usernames are the part of the email before the @ sign.
  """
  def resolve_mentions(content) when is_binary(content) do
    usernames =
      ~r/(?:^|\s)@([\w.+-]+)/
      |> Regex.scan(content)
      |> Enum.map(fn [_full, username] -> String.downcase(username) end)
      |> Enum.uniq()

    if usernames == [] do
      []
    else
      alias Hermes.Accounts.User

      from(u in User,
        where: fragment("lower(split_part(?, '@', 1))", u.email) in ^usernames
      )
      |> Repo.all()
    end
  end

  def resolve_mentions(_), do: []

  defp trigger_mention_notifications(_comment, []), do: :ok

  defp trigger_mention_notifications(comment, mentioned_users) do
    Enum.each(mentioned_users, fn user ->
      if user.id != comment.user_id do
        %{comment_id: comment.id, mentioned_user_id: user.id}
        |> Hermes.Workers.MentionNotificationWorker.new()
        |> Oban.insert()
      end
    end)
  end

  defp trigger_request_created_notification(request) do
    %{request_id: request.id, type: "created"}
    |> Hermes.Workers.RequestNotificationWorker.new()
    |> Oban.insert()
  end

  # GitHub sync hooks

  @doc """
  Returns a request preloaded with its `github_issue` association.
  """
  def get_request_with_github_issue(id) do
    Request
    |> Repo.get!(id)
    |> Repo.preload([
      :requesting_team,
      :assigned_to_team,
      :created_by,
      :discarded_by,
      :github_issue,
      :parent
    ])
    |> annotate_epic()
  end

  defp trigger_github_sync(request, action, extra \\ %{}) do
    if github_integration_enabled?() do
      Map.merge(%{action: action, request_id: request.id}, extra)
      |> Hermes.Workers.GitHubSyncWorker.new()
      |> Oban.insert()
    else
      {:ok, :feature_disabled}
    end
  end

  defp trigger_github_sync_on_update(updated, original, changes) do
    cond do
      not github_integration_enabled?() ->
        :ok

      is_nil(get_github_issue(updated.id)) ->
        :ok

      true ->
        if Map.has_key?(changes, :status) and updated.status != original.status do
          trigger_github_sync(updated, "project_move", %{status: updated.status})
        end

        if content_fields_changed?(changes) do
          trigger_github_sync(updated, "update")
        end

        :ok
    end
  end

  defp content_fields_changed?(changes) do
    Enum.any?(
      [
        :title,
        :description,
        :priority,
        :kind,
        :target_user_type,
        :current_situation,
        :goal_description,
        :data_description,
        :goal_target,
        :expected_output
      ],
      &Map.has_key?(changes, &1)
    )
  end

  defp trigger_github_comment_sync(comment) do
    if github_integration_enabled?() do
      %{action: "comment", comment_id: comment.id}
      |> Hermes.Workers.GitHubSyncWorker.new()
      |> Oban.insert()
    else
      {:ok, :feature_disabled}
    end
  end

  @doc """
  Returns true when the GitHub integration can run.

  The in-memory dev adapter is always considered enabled (no creds needed).
  The HTTP adapter requires `HERMES_GITHUB_TOKEN` + `HERMES_GITHUB_OWNER`.
  """
  def github_integration_enabled? do
    case GitHub.adapter() do
      Hermes.Services.GitHub.InMemory ->
        true

      _ ->
        cfg = Application.get_env(:hermes, :github, [])
        cfg[:token] not in [nil, ""] and cfg[:owner] not in [nil, ""]
    end
  end

  defp get_github_issue(request_id) do
    Repo.get_by(GitHubIssue, request_id: request_id)
  end

  @doc """
  Synchronously creates a GitHub issue for an existing request and persists
  the link. Used by the manual "Create issue" button on the edit page.

  Options:
    * `:repo` — override the default repo
  """
  def create_github_issue_for_request(%Request{} = request, opts \\ []) do
    cond do
      not github_integration_enabled?() ->
        {:error, :integration_disabled}

      not is_nil(get_github_issue(request.id)) ->
        {:error, :already_linked}

      true ->
        case GitHub.create_issue(annotate_epic(request), opts) do
          {:ok, %{owner: owner, repo: repo, number: number, url: url}} ->
            with {:ok, issue} <-
                   insert_github_issue(request.id, %{
                     owner: owner,
                     repo: repo,
                     number: number,
                     url: url,
                     state: "open"
                   }) do
              issue = maybe_post_link_comment(issue, request)
              cascade_subtasks_to_github(request, issue, opts)
              {:ok, issue}
            end

          {:error, _} = err ->
            err
        end
    end
  end

  @doc """
  Links an existing GitHub issue to a request.

  `reference` may be a bare number/`#N` (uses default repo) or a full
  `https://github.com/owner/repo/issues/N` URL.
  """
  def link_github_issue(%Request{} = request, reference) when is_binary(reference) do
    with :ok <- ensure_not_linked(request),
         {:ok, {owner, repo, number}} <- GitHub.parse_issue_reference(reference),
         {:ok, {resolved_owner, resolved_repo}} <- resolve_link_target(owner, repo),
         {:ok, %{url: url, state: state, title: title}} <-
           GitHub.get_issue(resolved_owner, resolved_repo, number) do
      # Linking only records the existing GH issue — no cascade, no sub-issue
      # creation, no body/label mutation. The pre-existing GH structure is
      # preserved; the title gains a `[Hermes #<id>]` prefix and reachability
      # back to Hermes is added as a comment.
      with {:ok, issue} <-
             insert_github_issue(request.id, %{
               owner: resolved_owner,
               repo: resolved_repo,
               number: number,
               url: url,
               state: state
             }) do
        # Reuse the title just fetched to avoid a redundant GitHub read.
        maybe_prefix_issue_title(issue, request, current_title: title)
        {:ok, maybe_post_link_comment(issue, request)}
      end
    end
  end

  # Posts the "Linked to Hermes" comment and persists its id for later deletion.
  # Best-effort: a failed comment never blocks linking.
  defp maybe_post_link_comment(%GitHubIssue{} = issue, %Request{} = request) do
    case GitHub.create_link_comment(issue, request) do
      {:ok, comment_id} ->
        case issue
             |> GitHubIssue.changeset(%{link_comment_id: comment_id})
             |> Repo.update() do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            Logger.warning(
              "link comment persist failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(reason)}"
            )

            issue
        end

      {:error, reason} ->
        Logger.warning(
          "link comment failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(reason)}"
        )

        issue
    end
  end

  # Prepends `[Hermes #<id>]` to the existing issue title on link.
  # Best-effort: a failed title update never blocks linking.
  defp maybe_prefix_issue_title(%GitHubIssue{} = issue, %Request{} = request, opts \\ []) do
    case GitHub.prefix_issue_title(issue, request, opts) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "prefix issue title failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp ensure_not_linked(%Request{} = request) do
    case get_github_issue(request.id) do
      nil -> :ok
      _ -> {:error, :already_linked}
    end
  end

  defp resolve_link_target(nil, nil), do: GitHub.default_target()

  defp resolve_link_target(owner, repo) when is_binary(owner) and is_binary(repo) do
    {:ok, {owner, repo}}
  end

  defp insert_github_issue(request_id, attrs) do
    result =
      %GitHubIssue{}
      |> GitHubIssue.changeset(
        Map.merge(attrs, %{
          request_id: request_id,
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      )
      |> Repo.insert()

    with {:ok, issue} <- result do
      {:ok, maybe_add_to_project(issue)}
    end
  end

  defp maybe_add_to_project(%GitHubIssue{} = issue) do
    cond do
      not is_nil(issue.project_item_id) ->
        issue

      not project_configured?() ->
        issue

      true ->
        with {:ok, node_id} <- GitHub.get_issue_node_id(issue.owner, issue.repo, issue.number),
             {:ok, item_id} <- ensure_project_item(node_id),
             {:ok, updated} <-
               issue
               |> GitHubIssue.changeset(%{project_item_id: item_id})
               |> Repo.update() do
          updated
        else
          {:error, :missing_project_config} ->
            issue

          {:error, reason} ->
            Logger.warning(
              "GitHub.add_issue_to_project failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(reason)}"
            )

            issue
        end
    end
  end

  defp ensure_project_item(node_id) do
    case GitHub.find_project_item(node_id) do
      {:ok, item_id} when is_binary(item_id) ->
        Logger.info("GitHub.add_issue_to_project skipped: existing item=#{item_id}")
        {:ok, item_id}

      _ ->
        GitHub.add_issue_to_project(node_id)
    end
  end

  defp project_configured? do
    case GitHub.adapter() do
      Hermes.Services.GitHub.InMemory ->
        true

      _ ->
        cfg = Application.get_env(:hermes, :github, [])
        cfg[:project_id] not in [nil, ""]
    end
  end

  @doc """
  Removes the GitHub issue link from a request. Also removes the linked
  project item (the GitHub issue itself is untouched).
  """
  def unlink_github_issue(%Request{} = request) do
    case get_github_issue(request.id) do
      nil ->
        {:error, :not_linked}

      issue ->
        maybe_delete_link_comment(issue)
        maybe_remove_project_item(issue)
        Repo.delete(issue)
    end
  end

  # Best-effort: a failed comment delete never blocks unlinking.
  defp maybe_delete_link_comment(%GitHubIssue{link_comment_id: nil}), do: :ok

  defp maybe_delete_link_comment(%GitHubIssue{} = issue) do
    case GitHub.delete_link_comment(issue) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "delete link comment failed issue=#{issue.owner}/#{issue.repo}##{issue.number} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp maybe_remove_project_item(%GitHubIssue{project_item_id: nil}), do: :ok

  defp maybe_remove_project_item(%GitHubIssue{project_item_id: item_id} = issue) do
    case GitHub.remove_item(item_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "remove_item failed issue=#{issue.owner}/#{issue.repo}##{issue.number} item=#{item_id} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  # Cascade subtask GH issues + sub-issue linkage when parent is linked.
  defp cascade_subtasks_to_github(%Request{parent_id: nil} = parent, parent_issue, opts) do
    parent.id
    |> list_subtasks()
    |> Enum.each(fn sub ->
      if sub.status != "discarded" do
        sync_subtask_to_github_parent(sub, parent_issue, opts)
      end
    end)
  end

  defp cascade_subtasks_to_github(_subtask_parent, _issue, _opts), do: :ok

  defp sync_subtask_to_github_parent(%Request{} = subtask, parent_issue, opts) do
    existing = get_github_issue(subtask.id)

    cond do
      not github_integration_enabled?() ->
        :ok

      not is_nil(existing) ->
        # already linked — just attach sub-issue relationship
        attach_sub_issue(parent_issue, existing)

      # Creation suppressed: a subtask of an already-linked parent stays
      # Hermes-only unless it is explicitly imported or pushed.
      Keyword.get(opts, :create, true) == false ->
        :ok

      true ->
        case GitHub.create_issue(subtask, opts) do
          {:ok, %{owner: o, repo: r, number: n, url: u}} ->
            case insert_github_issue(subtask.id, %{
                   owner: o,
                   repo: r,
                   number: n,
                   url: u,
                   state: "open"
                 }) do
              {:ok, child_issue} ->
                attach_sub_issue(parent_issue, child_issue)

              {:error, reason} ->
                Logger.warning(
                  "cascade_subtask insert failed subtask_id=#{subtask.id} reason=#{inspect(reason)}"
                )

                :ok
            end

          {:error, reason} ->
            Logger.warning(
              "cascade_subtask GH.create_issue failed subtask_id=#{subtask.id} reason=#{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp attach_sub_issue(%GitHubIssue{} = parent, %GitHubIssue{} = child) do
    with {:ok, parent_node} <- GitHub.get_issue_node_id(parent.owner, parent.repo, parent.number),
         {:ok, child_node} <- GitHub.get_issue_node_id(child.owner, child.repo, child.number),
         :ok <- maybe_add_sub_issue(parent_node, child_node, parent, child) do
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "add_sub_issue failed parent=#{parent.number} child=#{child.number} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp maybe_add_sub_issue(parent_node, child_node, parent, child) do
    case GitHub.sub_issue_attached?(parent_node, child_node) do
      {:ok, true} ->
        Logger.info(
          "add_sub_issue skipped: already attached parent=##{parent.number} child=##{child.number}"
        )

        :ok

      _ ->
        case GitHub.add_sub_issue(parent_node, child_node) do
          {:ok, _} -> :ok
          err -> err
        end
    end
  end

  # --- Status mappings (Hermes <-> GitHub Projects v2) ---

  def list_status_mappings do
    GitHubStatusMapping
    |> order_by([m], asc: m.hermes_status)
    |> Repo.all()
  end

  def get_status_mapping!(id), do: Repo.get!(GitHubStatusMapping, id)

  def upsert_status_mapping(attrs) do
    option_id = Map.get(attrs, "github_option_id") || Map.get(attrs, :github_option_id)

    case option_id && Repo.get_by(GitHubStatusMapping, github_option_id: option_id) do
      %GitHubStatusMapping{} = existing ->
        existing |> GitHubStatusMapping.changeset(attrs) |> Repo.update()

      _ ->
        %GitHubStatusMapping{} |> GitHubStatusMapping.changeset(attrs) |> Repo.insert()
    end
  end

  def delete_status_mapping(%GitHubStatusMapping{} = mapping), do: Repo.delete(mapping)

  def change_status_mapping(%GitHubStatusMapping{} = mapping, attrs \\ %{}),
    do: GitHubStatusMapping.changeset(mapping, attrs)

  @doc """
  Calls GitHub to list status field options for the configured project and
  upserts a mapping row for each option (hermes_status left blank if new).
  """
  def sync_status_mappings_from_github do
    case GitHub.list_status_options() do
      {:ok, options} ->
        existing_by_option =
          GitHubStatusMapping
          |> Repo.all()
          |> Map.new(&{&1.github_option_id, &1})

        new_options =
          options
          |> Enum.reject(fn %{id: id} -> Map.has_key?(existing_by_option, id) end)

        Enum.each(options, fn %{id: id, name: name} ->
          case Map.get(existing_by_option, id) do
            nil ->
              :ok

            mapping ->
              case mapping
                   |> GitHubStatusMapping.changeset(%{"github_option_name" => name})
                   |> Repo.update() do
                {:ok, _} ->
                  :ok

                {:error, reason} ->
                  Logger.warning(
                    "sync_status_mappings_from_github: failed to update option #{id}: #{inspect(reason)}"
                  )
              end
          end
        end)

        {:ok, %{existing: list_status_mappings(), pending_options: new_options}}

      {:error, _} = err ->
        err
    end
  end

  # --- Reverse-sync (GitHub webhook -> Hermes) ---

  @doc """
  Handles an `issues` webhook event payload. Updates the linked
  `github_issues.state` so the request view reflects the GitHub state, and
  records the transition in the request's change history when the state
  actually changed (so issue open/close is a tracked event).

  Accepts the issue map directly (with `repository_url`, `number`, `state`).
  """
  def handle_issue_event(%{"number" => number, "state" => state} = issue) do
    {owner, repo} = parse_repo_from_issue(issue)

    case Repo.get_by(GitHubIssue, owner: owner, repo: repo, number: number) do
      nil ->
        :ok

      %GitHubIssue{} = link ->
        old_state = link.state

        link
        |> GitHubIssue.changeset(%{
          state: state,
          last_sync_source: "webhook",
          last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
        |> case do
          {:ok, _} ->
            maybe_log_issue_state_change(link.request_id, old_state, state)
            :ok

          {:error, changeset} ->
            {:error, changeset.errors}
        end
    end
  end

  def handle_issue_event(_), do: :ok

  # Records the GitHub issue open/close transition in the request history.
  # No-op when the state is unchanged (e.g. an `edited` event that didn't
  # touch the issue state). A failed log must not fail the webhook.
  defp maybe_log_issue_state_change(_request_id, state, state), do: :ok

  defp maybe_log_issue_state_change(request_id, old_state, new_state) do
    case log_change(request_id, nil, "updated", %{
           field: "github_issue_state",
           old_value: old_state,
           new_value: new_state,
           changes: %{"source" => "github_webhook", "event_type" => "issues"}
         }) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "GitHub webhook could not log issue state change for request #{request_id}: #{inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp parse_repo_from_issue(%{"repository_url" => url}) when is_binary(url) do
    case Regex.run(~r{repos/([^/]+)/([^/]+)$}, url) do
      [_, o, r] -> {o, r}
      _ -> {nil, nil}
    end
  end

  defp parse_repo_from_issue(%{"owner" => o, "repo" => r}), do: {o, r}
  defp parse_repo_from_issue(_), do: {nil, nil}

  @doc """
  Handles a `projects_v2_item` webhook payload. Resolves the linked
  Hermes request via the project_item_id and updates its status when
  the status column moved.

  Accepts the raw `projects_v2_item` map from the webhook plus optional
  `changes` data (when called from controller, pass the top-level payload).
  """
  def handle_project_item_event(payload) when is_map(payload) do
    with %{"id" => item_id} <- payload,
         %GitHubIssue{} = link <- Repo.get_by(GitHubIssue, project_item_id: item_id) do
      apply_project_item_change(link, payload)
    else
      _ -> :ok
    end
  end

  # The `projects_v2_item` webhook fires once per single field change. Dispatch
  # on the changed field's type/name so each tracked param has its own path.
  # This is the single extension point for syncing more project fields later.
  @deadline_field_name "End date"

  defp apply_project_item_change(link, payload) do
    cond do
      extract_field_type(payload) == "date" and
          extract_field_name(payload) == @deadline_field_name ->
        apply_deadline_from_webhook(link.request_id, extract_field_value(payload))

      not is_nil(extract_status_option_id(payload)) ->
        apply_status_change(link, payload)

      true ->
        :ok
    end
  end

  defp apply_status_change(link, payload) do
    option_id = extract_status_option_id(payload)
    option_name = extract_status_option_name(payload)
    mapping = Repo.get_by(GitHubStatusMapping, github_option_id: option_id)

    case mapping do
      %GitHubStatusMapping{hermes_status: hermes_status} ->
        with :ok <- update_link_from_webhook(link, option_id, option_name) do
          apply_status_to_request(link.request_id, hermes_status)
        end

      nil ->
        Logger.warning(
          "GitHub webhook status mapping missing option_id=#{option_id} name=#{inspect(option_name)}"
        )

        update_link_from_webhook(link, option_id, option_name)
    end
  end

  defp extract_field_type(%{"changes" => %{"field_value" => %{"field_type" => type}}}), do: type
  defp extract_field_type(_), do: nil

  defp extract_field_name(%{"changes" => %{"field_value" => %{"field_name" => name}}}), do: name
  defp extract_field_name(_), do: nil

  defp extract_field_value(%{"changes" => %{"field_value" => %{"to" => to}}}), do: to
  defp extract_field_value(_), do: nil

  defp extract_status_option_id(%{"changes" => %{"field_value" => %{"to" => %{"id" => id}}}}),
    do: id

  defp extract_status_option_id(_), do: nil

  defp extract_status_option_name(%{
         "changes" => %{"field_value" => %{"to" => %{"name" => name}}}
       }),
       do: name

  defp extract_status_option_name(_), do: nil

  defp update_link_from_webhook(%GitHubIssue{} = link, option_id, option_name) do
    link
    |> GitHubIssue.changeset(%{
      project_status: option_name || option_id,
      last_sync_source: "webhook",
      last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset.errors}
    end
  end

  defp apply_status_to_request(request_id, hermes_status) do
    case Repo.get(Request, request_id) do
      nil ->
        Logger.warning("GitHub webhook: request #{request_id} not found, skipping status update")

        :ok

      %Request{status: ^hermes_status} ->
        :ok

      request ->
        request
        |> Request.changeset(%{status: hermes_status})
        |> Repo.update()
        |> case do
          {:ok, _} ->
            log_change(request_id, nil, "updated", %{
              field: "status",
              old_value: request.status,
              new_value: hermes_status,
              changes: %{"source" => "github_webhook"}
            })

            :ok

          {:error, changeset} ->
            Logger.warning(
              "GitHub webhook could not update request #{request_id} status: #{inspect(changeset.errors)}"
            )

            {:error, changeset.errors}
        end
    end
  end

  # Syncs the GitHub project "End date" field into `Request.deadline`. This is
  # webhook-IN only: `:deadline` is intentionally NOT in `content_fields_changed?/1`,
  # so updating it here never enqueues an outbound sync — no feedback loop.
  defp apply_deadline_from_webhook(request_id, raw_value) do
    deadline = parse_webhook_date(raw_value)

    case Repo.get(Request, request_id) do
      nil ->
        Logger.warning(
          "GitHub webhook: request #{request_id} not found, skipping deadline update"
        )

        :ok

      %Request{deadline: ^deadline} ->
        :ok

      request ->
        request
        |> Request.changeset(%{deadline: deadline})
        |> Repo.update()
        |> case do
          {:ok, _} ->
            log_change(request_id, nil, "updated", %{
              field: "deadline",
              old_value: to_string(request.deadline),
              new_value: to_string(deadline),
              changes: %{"source" => "github_webhook", "event_type" => "projects_v2_item"}
            })

            :ok

          {:error, changeset} ->
            Logger.warning(
              "GitHub webhook could not update request #{request_id} deadline: #{inspect(changeset.errors)}"
            )

            {:error, changeset.errors}
        end
    end
  end

  # GitHub does not publish the exact `to` shape for date fields, so parse
  # defensively: a bare ISO8601 string, a wrapping map, or nil/empty (cleared).
  defp parse_webhook_date(nil), do: nil
  defp parse_webhook_date(""), do: nil

  defp parse_webhook_date(value) when is_binary(value) do
    # Accept full ISO8601 dates and datetime strings ("2026-12-31T00:00:00Z").
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_webhook_date(%{"date" => date}), do: parse_webhook_date(date)
  defp parse_webhook_date(%{"value" => value}), do: parse_webhook_date(value)
  defp parse_webhook_date(_), do: nil

  defp trigger_comment_notification(comment) do
    %{comment_id: comment.id}
    |> Hermes.Workers.CommentNotificationWorker.new()
    |> Oban.insert()
  end

  def get_comment!(id) do
    RequestComment
    |> Repo.get!(id)
    |> Repo.preload(:user)
  end

  def get_comment(id) do
    case Repo.get(RequestComment, id) do
      nil -> nil
      comment -> Repo.preload(comment, :user)
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  def change_comment(%RequestComment{} = comment, attrs \\ %{}) do
    RequestComment.update_changeset(comment, attrs)
  end

  def update_comment(%RequestComment{} = comment, attrs) do
    comment
    |> RequestComment.update_changeset(attrs)
    |> Repo.update()
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

  # Image functions

  def list_request_images(request_id) do
    from(i in RequestImage, where: i.request_id == ^request_id, order_by: [asc: i.inserted_at])
    |> Repo.all()
  end

  def upload_request_image(request_id, %{
        path: path,
        client_name: filename,
        content_type: content_type
      }) do
    safe_filename = Path.basename(filename) |> String.replace(~r/[^\w.\-]/, "_")

    with {:ok, binary} <- File.read(path) do
      size = byte_size(binary)
      key = "hermes/#{env()}/requests/#{request_id}/#{Ecto.UUID.generate()}-#{safe_filename}"

      with {:ok, _} <- Storage.upload(key, binary, content_type) do
        %RequestImage{}
        |> RequestImage.changeset(%{
          request_id: request_id,
          key: key,
          filename: filename,
          content_type: content_type,
          size: size
        })
        |> Repo.insert()
      end
    end
  end

  def delete_request_image(%RequestImage{} = image) do
    with {:ok, _} <- Storage.delete(image.key),
         {:ok, _} <- Repo.delete(image) do
      :ok
    end
  end

  def image_url(%RequestImage{key: key}), do: Storage.public_url(key)

  defp env, do: Application.get_env(:hermes, :env, :prod)
end
