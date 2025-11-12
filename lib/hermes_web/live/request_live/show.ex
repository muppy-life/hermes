defmodule HermesWeb.RequestLive.Show do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Accounts
  alias HermesWeb.NavigationHistory

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    request = Requests.get_request!(id)
    changes = Requests.list_request_changes(id)
    comments = Requests.list_request_comments(id)

    {:ok,
     socket
     |> NavigationHistory.assign_return_path(default: ~p"/requests")
     |> assign(:page_title, "Request Details")
     |> assign(:request, request)
     |> assign(:changes, changes)
     |> assign(:comments, comments)
     |> assign(:comment_content, "")
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
    current_user = socket.assigns[:current_user]
    user_id = if current_user, do: current_user.id, else: nil

    case Requests.update_request(socket.assigns.request, request_params, user_id) do
      {:ok, _updated_request} ->
        # Reload the request with all associations preloaded
        request_id = socket.assigns.request.id
        updated_request = Requests.get_request!(request_id)
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
         |> push_navigate(to: ~p"/requests")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, "Failed to delete request")}
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
         |> assign(:comment_content, "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add comment")}
    end
  end

  def handle_event("update_comment", %{"content" => content}, socket) do
    {:noreply, assign(socket, :comment_content, content)}
  end

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
end
