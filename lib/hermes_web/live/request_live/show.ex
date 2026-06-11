defmodule HermesWeb.RequestLive.Show do
  use HermesWeb, :live_view

  require Logger

  alias Hermes.Accounts
  alias Hermes.Requests
  alias HermesWeb.RequestLive.UploadErrors

  @max_image_size 14 * 1_024 * 1_024

  @doc "GitHub logo mark."
  attr :class, :string, default: "size-4"

  def github_icon(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    request = Requests.get_request_with_github_issue(id)
    changes = Requests.list_request_changes(id)
    comments = Requests.list_request_comments(id)
    images = Requests.list_request_images(id)
    subtasks = Requests.list_subtasks(id)

    # Subscribe to updates for this request
    Phoenix.PubSub.subscribe(Hermes.PubSub, "request:#{id}")

    # Trigger diagram generation if missing (only when feature is enabled)
    if Requests.diagram_generation_enabled?() and
         (is_nil(request.solution_diagram) or request.solution_diagram == "") do
      Requests.trigger_diagram_generation_for_request(id)
    end

    current_user = socket.assigns[:current_user]
    can_set_deadline = request.assigned_to_team_id == current_user.team_id

    relevant_team_ids =
      [request.requesting_team_id, request.assigned_to_team_id]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    mentionable_users =
      Accounts.list_users()
      |> Enum.filter(fn u -> u.team_id in relevant_team_ids end)
      |> Enum.map(fn u ->
        %{id: u.id, username: u.email |> String.split("@") |> List.first()}
      end)

    {:ok,
     socket
     |> assign(:page_title, "Request Details")
     |> assign(:request, request)
     |> assign(:changes, changes)
     |> assign(:comments, comments)
     |> assign(:images, images)
     |> assign(:subtasks, subtasks)
     |> assign(:show_edit_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:show_deadline_modal, false)
     |> assign(:show_discard_modal, false)
     |> assign(:discard_category, List.first(Requests.discard_categories()))
     |> assign(:discard_reason, "")
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_comment_form, nil)
     |> assign(:selected_date, request.deadline || Date.utc_today())
     |> assign(:can_set_deadline, can_set_deadline)
     |> assign(:solution_tab, "goal")
     |> assign(:diagram_feature_enabled, Requests.diagram_generation_enabled?())
     |> assign(:teams, Accounts.list_teams())
     |> assign(:mentionable_users, mentionable_users)
     |> assign(:github_enabled, Requests.github_integration_enabled?())
     |> assign(:github_link_form, to_form(%{"reference" => ""}, as: :github_link))
     |> assign(:show_github_subtask_modal, false)
     |> assign(:github_subtask_candidates, [])
     |> assign(:github_subtask_selected, MapSet.new())
     |> assign(:form, to_form(Requests.change_request(request)))
     |> allow_upload(:images,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 10,
       max_file_size: @max_image_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("switch_solution_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :solution_tab, tab)}
  end

  @impl true
  def handle_event("open_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, true)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("open_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("validate", %{"request" => request_params}, socket) do
    changeset = Requests.change_request(socket.assigns.request, request_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"request" => request_params}, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil

    case Requests.update_request(socket.assigns.request, request_params, user_id) do
      {:ok, _updated_request} ->
        # Reload the request with all associations preloaded
        request_id = socket.assigns.request.id
        updated_request = Requests.get_request_with_github_issue(request_id)
        changes = Requests.list_request_changes(request_id)

        {:noreply,
         socket
         |> assign(:request, updated_request)
         |> assign(:changes, changes)
         |> assign(:show_edit_modal, false)
         |> assign(:form, to_form(Requests.change_request(updated_request)))
         |> put_flash(:info, "Request updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("confirm_delete", _params, socket) do
    request = socket.assigns.request

    case Requests.delete_request(request) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request deleted successfully")
         |> push_navigate(to: ~p"/backlog")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, "Failed to delete request")}
    end
  end

  def handle_event("open_deadline_modal", _params, socket) do
    {:noreply, assign(socket, :show_deadline_modal, true)}
  end

  def handle_event("close_deadline_modal", _params, socket) do
    {:noreply, assign(socket, :show_deadline_modal, false)}
  end

  def handle_event("update_selected_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:noreply, assign(socket, :selected_date, date)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_deadline", _params, socket) do
    request = socket.assigns.request
    selected_date = socket.assigns.selected_date
    current_user = socket.assigns[:current_user]

    # Verify user is from assigned team
    if request.assigned_to_team_id != current_user.team_id do
      {:noreply,
       socket
       |> assign(:show_deadline_modal, false)
       |> put_flash(:error, "Only the assigned team can set the deadline")}
    else
      case Requests.update_request(request, %{deadline: selected_date}, current_user.id) do
        {:ok, updated_request} ->
          {:noreply,
           socket
           |> assign(:request, updated_request)
           |> assign(:show_deadline_modal, false)
           |> put_flash(:info, "Deadline set successfully")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> assign(:show_deadline_modal, false)
           |> put_flash(:error, "Failed to set deadline")}
      end
    end
  end

  def handle_event("add_comment", %{"content" => content}, socket) do
    current_user = socket.assigns[:current_user]

    attrs = %{
      request_id: socket.assigns.request.id,
      user_id: current_user.id,
      content: content
    }

    case Requests.create_comment(attrs) do
      {:ok, _comment} ->
        comments = Requests.list_request_comments(socket.assigns.request.id)

        {:noreply,
         socket
         |> assign(:comments, comments)
         |> push_event("clear_comment_input", %{})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add comment")}
    end
  end

  def handle_event("start_edit_comment", %{"id" => id}, socket) do
    current_user = socket.assigns[:current_user]

    case Requests.get_comment(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Comment not found"))}

      %{user_id: user_id} when user_id != current_user.id ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      comment ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, comment.id)
         |> assign(:edit_comment_form, to_form(Requests.change_comment(comment), as: :comment))}
    end
  end

  def handle_event("cancel_edit_comment", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_comment_form, nil)}
  end

  def handle_event("validate_edit_comment", %{"comment" => params}, socket) do
    case Requests.get_comment(socket.assigns.editing_comment_id) do
      nil ->
        {:noreply, socket}

      comment ->
        changeset =
          comment
          |> Requests.change_comment(params)
          |> Map.put(:action, :validate)

        {:noreply, assign(socket, :edit_comment_form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("save_edit_comment", %{"id" => id, "comment" => params}, socket) do
    current_user = socket.assigns[:current_user]

    case Requests.get_comment(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Comment not found"))}

      %{user_id: user_id} when user_id != current_user.id ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      comment ->
        case Requests.update_comment(comment, params) do
          {:ok, _comment} ->
            comments = Requests.list_request_comments(socket.assigns.request.id)

            {:noreply,
             socket
             |> assign(:comments, comments)
             |> assign(:editing_comment_id, nil)
             |> assign(:edit_comment_form, nil)}

          {:error, changeset} ->
            {:noreply, assign(socket, :edit_comment_form, to_form(changeset, as: :comment))}
        end
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    current_user = socket.assigns[:current_user]

    case Requests.get_comment(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Comment not found"))}

      %{user_id: user_id} when user_id != current_user.id ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      comment ->
        case Requests.delete_comment(comment) do
          {:ok, _} ->
            comments = Requests.list_request_comments(socket.assigns.request.id)
            {:noreply, assign(socket, :comments, comments)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to delete comment"))}
        end
    end
  end

  def handle_event("change_status", %{"status" => "discarded"}, socket) do
    {:noreply,
     socket
     |> assign(:show_discard_modal, true)
     |> assign(:discard_category, List.first(Requests.discard_categories()))
     |> assign(:discard_reason, "")}
  end

  def handle_event("change_status", %{"status" => new_status}, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil

    case Requests.update_request(socket.assigns.request, %{status: new_status}, user_id) do
      {:ok, _updated_request} ->
        request_id = socket.assigns.request.id
        updated_request = Requests.get_request_with_github_issue(request_id)
        changes = Requests.list_request_changes(request_id)

        {:noreply,
         socket
         |> assign(:request, updated_request)
         |> assign(:changes, changes)
         |> assign(:form, to_form(Requests.change_request(updated_request)))
         |> put_flash(:info, gettext("Status updated successfully"))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update status"))}
    end
  end

  def handle_event("open_discard_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_discard_modal, true)
     |> assign(:discard_category, List.first(Requests.discard_categories()))
     |> assign(:discard_reason, "")}
  end

  def handle_event("close_discard_modal", _params, socket) do
    {:noreply, assign(socket, :show_discard_modal, false)}
  end

  def handle_event("update_discard_field", %{"field" => "category", "value" => v}, socket) do
    {:noreply, assign(socket, :discard_category, v)}
  end

  def handle_event("update_discard_field", %{"field" => "reason", "value" => v}, socket) do
    {:noreply, assign(socket, :discard_reason, v)}
  end

  def handle_event("confirm_discard", params, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil

    category = params["category"] || socket.assigns.discard_category
    reason = String.trim(params["reason"] || socket.assigns.discard_reason)

    cond do
      is_nil(user_id) ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      reason == "" ->
        {:noreply,
         socket
         |> assign(:discard_reason, reason)
         |> assign(:discard_category, category)
         |> put_flash(:error, gettext("Justification is required"))}

      true ->
        case Requests.discard_request(
               socket.assigns.request,
               %{category: category, reason: reason},
               user_id
             ) do
          {:ok, _} ->
            request_id = socket.assigns.request.id
            updated_request = Requests.get_request_with_github_issue(request_id)
            changes = Requests.list_request_changes(request_id)
            subtasks = Requests.list_subtasks(request_id)

            {:noreply,
             socket
             |> assign(:request, updated_request)
             |> assign(:changes, changes)
             |> assign(:subtasks, subtasks)
             |> assign(:show_discard_modal, false)
             |> assign(:form, to_form(Requests.change_request(updated_request)))
             |> put_flash(:info, gettext("Request discarded"))}

          {:error, :already_completed} ->
            {:noreply,
             socket
             |> assign(:show_discard_modal, false)
             |> put_flash(:error, gettext("Completed requests cannot be discarded"))}

          {:error, :already_discarded} ->
            {:noreply,
             socket
             |> assign(:show_discard_modal, false)
             |> put_flash(:error, gettext("Request is already discarded"))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to discard request"))}
        end
    end
  end

  def handle_event("restore_request", _params, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil

    case Requests.restore_request(socket.assigns.request, user_id) do
      {:ok, _} ->
        request_id = socket.assigns.request.id
        updated_request = Requests.get_request_with_github_issue(request_id)
        changes = Requests.list_request_changes(request_id)
        subtasks = Requests.list_subtasks(request_id)

        {:noreply,
         socket
         |> assign(:request, updated_request)
         |> assign(:changes, changes)
         |> assign(:subtasks, subtasks)
         |> assign(:form, to_form(Requests.change_request(updated_request)))
         |> put_flash(:info, gettext("Request restored"))}

      {:error, :parent_discarded} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Restore the parent request first to recover this subtask")
         )}

      {:error, :not_discarded} ->
        {:noreply, put_flash(socket, :error, gettext("Request is not discarded"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to restore request"))}
    end
  end

  def handle_event("add_subtask", %{"title" => title}, socket) do
    title = String.trim(title || "")
    current_user = socket.assigns[:current_user]

    cond do
      title == "" ->
        {:noreply, socket}

      is_nil(current_user) ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      true ->
        case Requests.create_subtask(socket.assigns.request, title, current_user.id) do
          {:ok, _subtask} ->
            subtasks = Requests.list_subtasks(socket.assigns.request.id)

            {:noreply,
             socket
             |> assign(:subtasks, subtasks)
             |> push_event("clear_subtask_input", %{})}

          {:error, :parent_discarded} ->
            {:noreply,
             put_flash(socket, :error, gettext("Cannot add subtasks to a discarded request"))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to add subtask"))}
        end
    end
  end

  def handle_event("toggle_subtask", %{"id" => id}, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil
    subtask = Enum.find(socket.assigns.subtasks, &(to_string(&1.id) == to_string(id)))

    if subtask do
      case Requests.toggle_subtask_status(subtask, user_id) do
        {:ok, _updated} ->
          subtasks = Requests.list_subtasks(socket.assigns.request.id)
          {:noreply, assign(socket, :subtasks, subtasks)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to update subtask"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_images", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  def handle_event("upload_images", _params, socket) do
    request_id = socket.assigns.request.id

    upload_results =
      consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
        {:ok,
         Requests.upload_request_image(request_id, %{
           path: path,
           client_name: entry.client_name,
           content_type: entry.client_type
         })}
      end)

    errors = Enum.filter(upload_results, &match?({:error, _}, &1))

    socket =
      if errors == [] do
        images = Requests.list_request_images(request_id)
        socket |> assign(:images, images) |> put_flash(:info, gettext("Images uploaded"))
      else
        Enum.each(errors, fn {:error, reason} ->
          Logger.error("Image upload failed: #{inspect(reason)}")
        end)

        put_flash(socket, :error, UploadErrors.format(errors))
      end

    {:noreply, socket}
  end

  def handle_event("delete_image", %{"id" => image_id}, socket) do
    request_id = socket.assigns.request.id
    image = Enum.find(socket.assigns.images, &(to_string(&1.id) == image_id))

    if image do
      case Requests.delete_request_image(image) do
        :ok ->
          images = Requests.list_request_images(request_id)
          {:noreply, assign(socket, :images, images)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to delete image"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("github_create_issue", _params, socket) do
    if Accounts.is_dev_team?(socket.assigns.current_user) do
      case Requests.create_github_issue_for_request(socket.assigns.request) do
        {:ok, issue} ->
          {:noreply,
           socket
           |> assign(:request, %{socket.assigns.request | github_issue: issue})
           |> put_flash(:info, "GitHub issue ##{issue.number} created")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, github_error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Only the dev team can create GitHub issues"))}
    end
  end

  def handle_event("github_link_issue", %{"github_link" => %{"reference" => reference}}, socket) do
    if Accounts.is_dev_team?(socket.assigns.current_user) do
      case Requests.link_github_issue(socket.assigns.request, reference) do
        {:ok, issue} ->
          socket =
            socket
            |> assign(:request, %{socket.assigns.request | github_issue: issue})
            |> assign(:github_link_form, to_form(%{"reference" => ""}, as: :github_link))
            |> put_flash(:info, "Linked GitHub issue ##{issue.number}")

          {:noreply, maybe_open_github_subtask_modal(socket)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, github_error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Only the dev team can link GitHub issues"))}
    end
  end

  def handle_event("toggle_github_subtask", %{"key" => key}, socket) do
    selected = socket.assigns.github_subtask_selected

    selected =
      if MapSet.member?(selected, key),
        do: MapSet.delete(selected, key),
        else: MapSet.put(selected, key)

    {:noreply, assign(socket, :github_subtask_selected, selected)}
  end

  def handle_event("cancel_github_subtask_modal", _params, socket) do
    {:noreply, close_github_subtask_modal(socket)}
  end

  def handle_event("import_github_subtasks", _params, socket) do
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil
    selected = socket.assigns.github_subtask_selected

    chosen =
      Enum.filter(
        socket.assigns.github_subtask_candidates,
        &MapSet.member?(selected, subtask_key(&1))
      )

    case Requests.import_github_subtasks(socket.assigns.request, chosen, user_id) do
      {:ok, tally} ->
        subtasks = Requests.list_subtasks(socket.assigns.request.id)
        {kind, message} = import_flash(tally)

        {:noreply,
         socket
         |> assign(:subtasks, subtasks)
         |> close_github_subtask_modal()
         |> put_flash(kind, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> close_github_subtask_modal()
         |> put_flash(:error, github_error_message(reason))}
    end
  end

  def handle_event("github_unlink", _params, socket) do
    if Accounts.is_dev_team?(socket.assigns.current_user) do
      case Requests.unlink_github_issue(socket.assigns.request) do
        {:ok, _issue} ->
          {:noreply,
           socket
           |> assign(:request, %{socket.assigns.request | github_issue: nil})
           |> put_flash(:info, "GitHub issue unlinked")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, github_error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Only the dev team can unlink GitHub issues"))}
    end
  end

  @impl true
  def handle_info({:diagram_generated, request_id}, socket) do
    # Reload the request to get the updated diagram
    updated_request = Requests.get_request_with_github_issue(request_id)

    {:noreply, assign(socket, :request, updated_request)}
  end

  # Fetches the linked parent issue's GitHub sub-issues; opens the import modal
  # (all preselected) only when there are unimported candidates.
  defp maybe_open_github_subtask_modal(socket) do
    case Requests.list_linkable_github_subtasks(socket.assigns.request) do
      {:ok, [_ | _] = candidates} ->
        selected = candidates |> Enum.map(&subtask_key/1) |> MapSet.new()

        socket
        |> assign(:github_subtask_candidates, candidates)
        |> assign(:github_subtask_selected, selected)
        |> assign(:show_github_subtask_modal, true)

      {:ok, []} ->
        # Linked, but the issue has no (unimported) sub-issues — nothing to offer.
        socket

      {:error, reason} ->
        # The link itself succeeded; only the sub-issue lookup failed. Surface it
        # so the user knows sub-issues could not be fetched, rather than silently
        # showing nothing.
        put_flash(
          socket,
          :error,
          "Linked, but could not load GitHub sub-issues: #{github_error_message(reason)}"
        )
    end
  end

  defp close_github_subtask_modal(socket) do
    socket
    |> assign(:show_github_subtask_modal, false)
    |> assign(:github_subtask_candidates, [])
    |> assign(:github_subtask_selected, MapSet.new())
  end

  defp subtask_key(%{owner: owner, repo: repo, number: number}), do: "#{owner}/#{repo}##{number}"

  # Builds the flash from the import tally. Any failures make it an error flash
  # so the user knows some selections were dropped and can retry.
  defp import_flash(%{imported: imported, failed: failed}) when failed > 0 do
    {:error, "Imported #{imported} subtask(s); #{failed} failed — please try again"}
  end

  defp import_flash(%{imported: imported}) do
    {:info, "Imported #{imported} subtask(s) from GitHub"}
  end

  defp github_error_message(:integration_disabled), do: "GitHub integration is not configured"
  defp github_error_message(:already_linked), do: "Request is already linked to an issue"
  defp github_error_message(:not_linked), do: "Request is not linked to an issue"
  defp github_error_message(:parent_not_linked), do: "Request is not linked to an issue"
  defp github_error_message(:invalid_reference), do: "Could not parse the issue reference"
  defp github_error_message(:missing_config), do: "Missing GitHub owner/repo configuration"
  defp github_error_message(:missing_token), do: "Missing GitHub token"
  defp github_error_message({:http_error, status, _}), do: "GitHub returned status #{status}"
  defp github_error_message({:transport_error, _}), do: "Could not reach GitHub"
  defp github_error_message(%Ecto.Changeset{}), do: "Could not save the issue link"
  defp github_error_message(reason), do: "GitHub error: #{inspect(reason)}"

  defp render_comment_content(content) do
    mention_regex = ~r/((?:^|\s)@[\w.+-]+)/

    segments =
      mention_regex
      |> Regex.split(content, include_captures: true)

    html =
      Enum.map_join(segments, fn segment ->
        case Regex.run(~r/^(\s*)(@[\w.+-]+)$/, segment) do
          [_, whitespace, mention] ->
            escaped_ws = Phoenix.HTML.html_escape(whitespace) |> Phoenix.HTML.safe_to_string()
            escaped_mention = Phoenix.HTML.html_escape(mention) |> Phoenix.HTML.safe_to_string()
            escaped_ws <> ~s(<span class="text-primary font-semibold">#{escaped_mention}</span>)

          _ ->
            Phoenix.HTML.html_escape(segment) |> Phoenix.HTML.safe_to_string()
        end
      end)

    Phoenix.HTML.raw(html)
  end

  defp upload_error_to_string(:too_large), do: gettext("File exceeds 14 MB limit")
  defp upload_error_to_string(:not_accepted), do: gettext("Only JPG and PNG files are allowed")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files selected")
  defp upload_error_to_string(_), do: gettext("Upload failed")

  defp humanize_field(field) when is_binary(field) do
    field
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_field(_), do: "Unknown field"

  defp format_change_value(nil), do: "(empty)"
  defp format_change_value(""), do: "(empty)"

  defp format_change_value(value) when byte_size(value) > 50 do
    String.slice(value, 0..47) <> "..."
  end

  defp format_change_value(value), do: value

  defp aging_days(%{updated_at: nil}), do: 0

  defp aging_days(%{updated_at: updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at, :day)
  end

  defp aging_class(days) when days <= 7, do: "aging-ok"
  defp aging_class(days) when days <= 30, do: "aging-warn"
  defp aging_class(_), do: "aging-bad"

  defp status_options do
    [
      {"new", gettext("New")},
      {"need_requirement", gettext("Need requirement")},
      {"pending", gettext("Pending")},
      {"future_planning", gettext("Future Planning")},
      {"todo_in_sprint", gettext("Todo in Sprint")},
      {"in_progress", gettext("In progress")},
      {"review", gettext("Review")},
      {"completed", gettext("Completed")},
      {"blocked", gettext("Blocked")},
      {"discarded", gettext("Discarded")}
    ]
  end

  defp discard_category_options do
    Enum.map(Hermes.Requests.discard_categories(), fn key ->
      {Atom.to_string(key), discard_category_label(key)}
    end)
  end

  defp discard_category_label(category) when is_binary(category) do
    discard_category_label(String.to_existing_atom(category))
  rescue
    ArgumentError -> gettext("Unknown")
  end

  defp discard_category_label(:duplicate), do: gettext("Duplicate")
  defp discard_category_label(:out_of_scope), do: gettext("Out of scope")
  defp discard_category_label(:not_technically_viable), do: gettext("Not technically viable")
  defp discard_category_label(:replaced_by_another), do: gettext("Replaced by another request")
  defp discard_category_label(:postponed_indefinitely), do: gettext("Postponed indefinitely")
  defp discard_category_label(:not_a_priority), do: gettext("Not a priority")
  defp discard_category_label(:no_resources_available), do: gettext("No resources available")
  defp discard_category_label(:no_longer_applicable), do: gettext("No longer applicable")
  defp discard_category_label(:other), do: gettext("Other reason")
  defp discard_category_label(_), do: gettext("Unknown")

  defp subtask_progress(subtasks) do
    active = Enum.reject(subtasks, &(&1.status == "discarded"))
    total = length(active)
    done = Enum.count(active, &(&1.status == "completed"))
    pct = if total > 0, do: round(done / total * 100), else: 0
    {done, total, pct}
  end
end
