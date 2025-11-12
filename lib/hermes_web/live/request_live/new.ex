defmodule HermesWeb.RequestLive.New do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("New Request"))
     |> assign(:current_step, 1)
     |> assign(:form_data, %{})
     |> assign(:teams, Accounts.list_teams())
     |> assign(:form, to_form(%{}, as: :request))}
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

    {:noreply,
     socket
     |> assign(:current_step, current_step + 1)
     |> assign(:form_data, form_data)
     |> assign(:form, to_form(form_data, as: :request))}
  end

  def handle_event("prev_step", _params, socket) do
    current_step = socket.assigns.current_step

    {:noreply,
     socket
     |> assign(:current_step, max(current_step - 1, 1))
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
        {:noreply,
         socket
         |> put_flash(:info, gettext("Request created successfully"))
         |> push_navigate(to: ~p"/requests")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please check the form for errors"))
         |> assign(:form, to_form(changeset))}
    end
  end

  defp generate_title(form_data) do
    kind = form_data["kind"] || "request"
    kind_label = case kind do
      "problem" -> "Problem"
      "new_need" -> "New Need"
      "improvement" -> "Improvement"
      _ -> "Request"
    end

    situation = form_data["current_situation"] || "Untitled"
    "#{kind_label}: #{String.slice(situation, 0..50)}"
  end
end
