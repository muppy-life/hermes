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
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by, :github_issue])
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
  The HTTP adapter requires `GITHUB_TOKEN` + `GITHUB_OWNER`.
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
        case GitHub.create_issue(request, opts) do
          {:ok, %{owner: owner, repo: repo, number: number, url: url}} ->
            insert_github_issue(request.id, %{
              owner: owner,
              repo: repo,
              number: number,
              url: url,
              state: "open"
            })

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
         {:ok, %{url: url, state: state}} <-
           GitHub.get_issue(resolved_owner, resolved_repo, number) do
      insert_github_issue(request.id, %{
        owner: resolved_owner,
        repo: resolved_repo,
        number: number,
        url: url,
        state: state
      })
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
             {:ok, item_id} <- GitHub.add_issue_to_project(node_id) do
          {:ok, updated} =
            issue
            |> GitHubIssue.changeset(%{project_item_id: item_id})
            |> Repo.update()

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
  Removes the GitHub issue link from a request. Does not touch GitHub.
  """
  def unlink_github_issue(%Request{} = request) do
    case get_github_issue(request.id) do
      nil -> {:error, :not_linked}
      issue -> Repo.delete(issue)
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
  `github_issues.state` so the request view reflects the GitHub state.

  Accepts the issue map directly (with `repository_url`, `number`, `state`).
  """
  def handle_issue_event(%{"number" => number, "state" => state} = issue) do
    {owner, repo} = parse_repo_from_issue(issue)

    case Repo.get_by(GitHubIssue, owner: owner, repo: repo, number: number) do
      nil ->
        :ok

      %GitHubIssue{} = link ->
        link
        |> GitHubIssue.changeset(%{
          state: state,
          last_sync_source: "webhook",
          last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

        :ok
    end
  end

  def handle_issue_event(_), do: :ok

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

  defp apply_project_item_change(link, payload) do
    option_id = extract_status_option_id(payload)
    option_name = extract_status_option_name(payload)

    cond do
      is_nil(option_id) ->
        :ok

      true ->
        mapping = Repo.get_by(GitHubStatusMapping, github_option_id: option_id)

        case mapping do
          %GitHubStatusMapping{hermes_status: hermes_status} ->
            update_link_from_webhook(link, option_id, option_name)
            apply_status_to_request(link.request_id, hermes_status)
            :ok

          nil ->
            Logger.warning(
              "GitHub webhook status mapping missing option_id=#{option_id} name=#{inspect(option_name)}"
            )

            update_link_from_webhook(link, option_id, option_name)
            :ok
        end
    end
  end

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

            :error
        end
    end
  end

  defp trigger_comment_notification(comment) do
    %{comment_id: comment.id}
    |> Hermes.Workers.CommentNotificationWorker.new()
    |> Oban.insert()
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
