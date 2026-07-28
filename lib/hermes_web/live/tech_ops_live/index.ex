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
     |> assign(:reporter_name, "")
     |> assign(:issue_origin_name, "")
     |> assign(:new_reporter, false)
     |> assign(:new_issue_origin, false)
     |> assign(:users, Accounts.list_dev_team())
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
     |> assign(:new_reporter, false)
     |> assign(:new_issue_origin, false)
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
         # A value no longer in the lookup list would vanish from a <select>,
         # so fall back to the free-text input to preserve it.
         |> assign(:new_reporter, orphan_value?(task.reporter, socket.assigns.reporters))
         |> assign(
           :new_issue_origin,
           orphan_value?(task.issue_origin, socket.assigns.issue_origins)
         )
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

  # Swaps a lookup field between picking an existing value and typing a new one.
  # Clears the field so the value left behind in the other input is not submitted.
  def handle_event("toggle_new_lookup", %{"field" => "reporter"}, socket) do
    {:noreply,
     socket
     |> assign(:new_reporter, !socket.assigns.new_reporter)
     |> assign(:reporter_name, "")}
  end

  def handle_event("toggle_new_lookup", %{"field" => "issue_origin"}, socket) do
    {:noreply,
     socket
     |> assign(:new_issue_origin, !socket.assigns.new_issue_origin)
     |> assign(:issue_origin_name, "")}
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

  # True when the task holds a lookup value that is absent from the current
  # options, so the <select> could not represent it.
  defp orphan_value?(%{id: id}, options), do: not Enum.any?(options, &(&1.id == id))
  defp orphan_value?(_, _), do: false

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
