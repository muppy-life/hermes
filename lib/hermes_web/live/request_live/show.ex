defmodule HermesWeb.RequestLive.Show do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    request = Requests.get_request!(id)

    {:ok,
     socket
     |> assign(:page_title, "Request Details")
     |> assign(:request, request)
     |> assign(:show_edit_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:teams, Accounts.list_teams())
     |> assign(:form, to_form(Requests.change_request(request)))}
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

  def handle_event("save", %{"request" => request_params}, socket) do
    case Requests.update_request(socket.assigns.request, request_params) do
      {:ok, _updated_request} ->
        # Reload the request with all associations preloaded
        updated_request = Requests.get_request!(socket.assigns.request.id)

        {:noreply,
         socket
         |> assign(:request, updated_request)
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
         |> push_navigate(to: ~p"/requests")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, "Failed to delete request")}
    end
  end
end
