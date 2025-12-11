defmodule HermesWeb.RequestLive.New do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Requests

  # Auto-save interval in milliseconds (5 seconds)
  @auto_save_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    # Restore draft from database if available
    {current_step, form_data} = load_draft(current_user.id)

    socket =
      socket
      |> assign(:page_title, gettext("New Request"))
      |> assign(:current_step, current_step)
      |> assign(:form_data, form_data)
      |> assign(:teams, Accounts.list_teams())
      |> assign(:return_to, ~p"/backlog")
      |> assign(:form, to_form(form_data, as: :request))

    # Schedule periodic auto-save only on connected mount
    if connected?(socket) do
      schedule_auto_save()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:auto_save, socket) do
    current_user = socket.assigns[:current_user]

    # Save current state to database
    save_draft(current_user.id, socket.assigns.current_step, socket.assigns.form_data)

    # Schedule next auto-save
    schedule_auto_save()

    {:noreply, socket}
  end

  defp schedule_auto_save do
    Process.send_after(self(), :auto_save, @auto_save_interval)
  end

  defp load_draft(user_id) do
    case Requests.get_draft(user_id) do
      nil -> {1, %{}}
      draft -> {draft.step, draft.form_data}
    end
  end

  defp save_draft(user_id, step, form_data) do
    Requests.save_draft(user_id, step, form_data)
  end

  defp clear_draft(user_id) do
    Requests.delete_draft(user_id)
  end

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    # Update single field in form_data (triggered by phx-blur on textareas)
    form_data = Map.put(socket.assigns.form_data, field, value)
    {:noreply, assign(socket, :form_data, form_data)}
  end

  @impl true
  def handle_event("next_step", params, socket) do
    current_step = socket.assigns.current_step

    # Handle both form submission and direct radio button clicks
    form_data =
      case params do
        %{"request" => request_params} ->
          Map.merge(socket.assigns.form_data, request_params)

        # Handle direct phx-click from radio buttons
        phx_values when is_map(phx_values) ->
          Map.merge(socket.assigns.form_data, phx_values)

        _ ->
          socket.assigns.form_data
      end

    next_step = current_step + 1

    # Save immediately on step change
    current_user = socket.assigns[:current_user]
    save_draft(current_user.id, next_step, form_data)

    {:noreply,
     socket
     |> assign(:current_step, next_step)
     |> assign(:form_data, form_data)
     |> assign(:form, to_form(form_data, as: :request))}
  end

  def handle_event("prev_step", _params, socket) do
    current_step = socket.assigns.current_step
    prev_step = max(current_step - 1, 1)

    # Save immediately on step change
    current_user = socket.assigns[:current_user]
    save_draft(current_user.id, prev_step, socket.assigns.form_data)

    {:noreply,
     socket
     |> assign(:current_step, prev_step)
     |> assign(:form, to_form(socket.assigns.form_data, as: :request))}
  end

  def handle_event("save", %{"request" => request_params}, socket) do
    current_user = socket.assigns[:current_user]
    form_data = Map.merge(socket.assigns.form_data, request_params)

    # Set defaults
    final_params =
      form_data
      |> Map.put("created_by_id", current_user.id)
      |> Map.put("requesting_team_id", current_user.team_id)
      |> Map.put("status", "pending")
      |> Map.put("title", generate_title(form_data))
      |> Map.put("description", form_data["current_situation"] || "")

    case Requests.create_request(final_params, current_user.id) do
      {:ok, _request} ->
        # Clear draft after successful creation
        clear_draft(current_user.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Request created successfully"))
         |> push_navigate(to: ~p"/backlog")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please check the form for errors"))
         |> assign(:form, to_form(changeset))}
    end
  end

  defp generate_title(form_data) do
    situation = form_data["current_situation"] || "Untitled"
    String.slice(situation, 0..50)
  end
end
