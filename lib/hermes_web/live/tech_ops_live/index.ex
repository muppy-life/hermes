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
     |> assign(:users, Accounts.list_users())
     |> load_tasks()}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    changeset = Task.changeset(%Task{status: :open}, %{"recorded_on" => Date.utc_today()})

    {:noreply,
     socket
     |> assign(:form_mode, :new)
     |> assign(:selected_task, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    task = TechOps.get_tech_ops_task!(String.to_integer(id))
    changeset = Task.changeset(task, %{})

    {:noreply,
     socket
     |> assign(:form_mode, :edit)
     |> assign(:selected_task, task)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, assign(socket, :show_form_modal, false)}
  end

  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    task = TechOps.get_tech_ops_task!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_task, task)
     |> assign(:show_delete_modal, true)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("validate", %{"task" => task_params}, socket) do
    task = socket.assigns.selected_task || %Task{}
    changeset = Task.changeset(task, task_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
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
  end

  defp save_task(socket, :new, task_params) do
    case TechOps.create_tech_ops_task(task_params) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_tasks()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Task created successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp save_task(socket, :edit, task_params) do
    task = socket.assigns.selected_task

    case TechOps.update_tech_ops_task(task, task_params) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_tasks()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Task updated successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp load_tasks(socket) do
    tasks = TechOps.list_tech_ops_tasks()

    socket
    |> stream(:tasks, tasks, reset: true)
    |> assign(:task_count, length(tasks))
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
