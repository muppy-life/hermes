defmodule HermesWeb.TechOpsLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.TechOps
  alias Hermes.TechOps.Task

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Tech Ops"))
     |> assign(:show_form_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:selected_task, nil)
     |> assign(:form_mode, :new)
     |> assign(:form, to_form(%{}))
     |> assign(:users, Accounts.list_tech_users())
     |> assign(:teams, Accounts.list_teams())
     |> load_lookups()
     |> load_tasks()}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    changeset =
      Task.changeset(%Task{status: :open}, %{
        "recorded_on" => Date.utc_today(),
        "responsible_id" => socket.assigns.current_user.id
      })

    {:noreply,
     socket
     |> assign(:form_mode, :new)
     |> assign(:selected_task, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:reporter_name, "")
     |> assign(:issue_origin_name, "")
     |> assign(:show_form_modal, true)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    case TechOps.get_tech_ops_task(id) do
      nil ->
        {:noreply, handle_missing_task(socket)}

      task ->
        changeset = Task.changeset(task, %{})

        {:noreply,
         socket
         |> assign(:form_mode, :edit)
         |> assign(:selected_task, task)
         |> assign(:form, to_form(changeset))
         |> assign(:reporter_name, lookup_name(task.reporter))
         |> assign(:issue_origin_name, lookup_name(task.issue_origin))
         |> assign(:show_form_modal, true)}
    end
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, assign(socket, :show_form_modal, false)}
  end

  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    case TechOps.get_tech_ops_task(id) do
      nil ->
        {:noreply, handle_missing_task(socket)}

      task ->
        {:noreply,
         socket
         |> assign(:selected_task, task)
         |> assign(:show_delete_modal, true)}
    end
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("validate", %{"task" => task_params}, socket) do
    task = socket.assigns.selected_task || %Task{}
    changeset = Task.changeset(task, task_params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:reporter_name, Map.get(task_params, "reporter_name", ""))
     |> assign(:issue_origin_name, Map.get(task_params, "issue_origin_name", ""))}
  end

  def handle_event("save", %{"task" => task_params}, socket) do
    save_task(socket, socket.assigns.form_mode, task_params)
  end

  def handle_event("confirm_delete", _params, socket) do
    case TechOps.delete_tech_ops_task(socket.assigns.selected_task) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_tasks()
         |> assign(:show_delete_modal, false)
         |> put_flash(:info, gettext("Task deleted successfully"))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, gettext("Failed to delete task"))}
    end
  rescue
    # Already deleted by another user; treat as done and refresh the list.
    Ecto.StaleEntryError ->
      {:noreply,
       socket
       |> load_tasks()
       |> assign(:show_delete_modal, false)
       |> put_flash(:info, gettext("Task deleted successfully"))}
  end

  defp save_task(socket, :new, task_params) do
    # Lookups (reporter / issue origin) are resolved atomically inside
    # create_tech_ops_task/1, so a rejected insert leaves no orphaned values.
    case TechOps.create_tech_ops_task(task_params) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_tasks()
         |> load_lookups()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Task created successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp save_task(socket, :edit, task_params) do
    # update_tech_ops_task/2 resolves lookups and updates in one transaction: if
    # the task was concurrently deleted, StaleEntryError rolls the whole thing
    # back (no orphaned lookups) and is handled below.
    case TechOps.update_tech_ops_task(socket.assigns.selected_task, task_params) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_tasks()
         |> load_lookups()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Task updated successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  rescue
    # The task was deleted by another user after this modal was opened.
    Ecto.StaleEntryError -> {:noreply, handle_missing_task(socket)}
  end

  defp load_tasks(socket) do
    tasks = TechOps.list_tech_ops_tasks()

    socket
    |> stream(:tasks, tasks, reset: true)
    |> assign(:task_count, length(tasks))
  end

  defp load_lookups(socket) do
    socket
    |> assign(:reporters, TechOps.list_reporters())
    |> assign(:issue_origins, TechOps.list_issue_origins())
  end

  defp lookup_name(%{name: name}), do: name
  defp lookup_name(_), do: ""

  # A task referenced by a stale row no longer exists (deleted by another user).
  # Close any open modal, drop the stale row via a reload, and inform the user.
  defp handle_missing_task(socket) do
    socket
    |> assign(:show_form_modal, false)
    |> assign(:show_delete_modal, false)
    |> load_tasks()
    |> put_flash(:error, gettext("This task no longer exists."))
  end

  # Translated status label for the UI.
  defp task_status_label(:open), do: gettext("Open")
  defp task_status_label(:in_progress), do: gettext("In progress")
  defp task_status_label(:blocked), do: gettext("Blocked")
  defp task_status_label(:resolved), do: gettext("Resolved")
  defp task_status_label(:closed), do: gettext("Closed")
  defp task_status_label(_), do: gettext("Unknown")

  defp task_status_options do
    Enum.map(Task.statuses(), &{task_status_label(&1), &1})
  end

  defp task_status_badge_class(:open), do: "bg-info/10 text-info"
  defp task_status_badge_class(:in_progress), do: "bg-warning/10 text-warning"
  defp task_status_badge_class(:blocked), do: "bg-error/10 text-error"
  defp task_status_badge_class(:resolved), do: "bg-success/10 text-success"
  defp task_status_badge_class(:closed), do: "bg-base-content/10 text-base-content/60"
  defp task_status_badge_class(_), do: "bg-base-content/10 text-base-content/60"
end
