defmodule HermesWeb.RequestLive.Edit do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Accounts
  alias HermesWeb.NavigationHistory

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    request = Requests.get_request!(id)

    {:ok,
     socket
     |> NavigationHistory.assign_return_path(default: ~p"/requests")
     |> assign(:page_title, "Edit Request")
     |> assign(:request, request)
     |> assign(:teams, Accounts.list_teams())
     |> assign(:form, to_form(Requests.change_request(request)))}
  end

  @impl true
  def handle_event("validate", %{"request" => request_params}, socket) do
    changeset = Requests.change_request(socket.assigns.request, request_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"request" => request_params}, socket) do
    case Requests.update_request(socket.assigns.request, request_params) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request updated successfully")
         |> push_navigate(to: ~p"/requests")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
