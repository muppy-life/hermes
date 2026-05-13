defmodule HermesWeb.RequestLive.Edit do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Requests
  alias HermesWeb.NavigationHistory

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    request = Requests.get_request_with_github_issue(id)

    {:ok,
     socket
     |> NavigationHistory.assign_return_path(default: ~p"/backlog")
     |> assign(:page_title, "Edit Request")
     |> assign(:request, request)
     |> assign(:teams, Accounts.list_teams())
     |> assign(:github_enabled, Requests.github_integration_enabled?())
     |> assign(:link_form, to_form(%{"reference" => ""}, as: :github_link))
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
         |> push_navigate(to: ~p"/backlog")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("github_create_issue", _params, socket) do
    case Requests.create_github_issue_for_request(socket.assigns.request) do
      {:ok, issue} ->
        {:noreply,
         socket
         |> assign(:request, %{socket.assigns.request | github_issue: issue})
         |> put_flash(:info, "GitHub issue ##{issue.number} created")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, github_error_message(reason))}
    end
  end

  def handle_event("github_link_issue", %{"github_link" => %{"reference" => reference}}, socket) do
    case Requests.link_github_issue(socket.assigns.request, reference) do
      {:ok, issue} ->
        {:noreply,
         socket
         |> assign(:request, %{socket.assigns.request | github_issue: issue})
         |> assign(:link_form, to_form(%{"reference" => ""}, as: :github_link))
         |> put_flash(:info, "Linked GitHub issue ##{issue.number}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, github_error_message(reason))}
    end
  end

  def handle_event("github_unlink", _params, socket) do
    case Requests.unlink_github_issue(socket.assigns.request) do
      {:ok, _issue} ->
        {:noreply,
         socket
         |> assign(:request, %{socket.assigns.request | github_issue: nil})
         |> put_flash(:info, "GitHub issue unlinked")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, github_error_message(reason))}
    end
  end

  defp github_error_message(:integration_disabled), do: "GitHub integration is not configured"
  defp github_error_message(:already_linked), do: "Request is already linked to an issue"
  defp github_error_message(:not_linked), do: "Request is not linked to an issue"
  defp github_error_message(:invalid_reference), do: "Could not parse the issue reference"
  defp github_error_message(:missing_config), do: "Missing GitHub owner/repo configuration"
  defp github_error_message(:missing_token), do: "Missing GitHub token"
  defp github_error_message({:http_error, status, _}), do: "GitHub returned status #{status}"
  defp github_error_message({:transport_error, _}), do: "Could not reach GitHub"
  defp github_error_message(%Ecto.Changeset{}), do: "Could not save the issue link"
  defp github_error_message(reason), do: "GitHub error: #{inspect(reason)}"
end
