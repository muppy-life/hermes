defmodule HermesWeb.Admin.ApiTokenLive.Index do
  @moduledoc """
  Admin management of API tokens used for REST/MCP access.

  Every admin creates their own token (the owner is always the current user) to
  connect an MCP client such as Claude; the raw token is shown once and never
  again. All admins can see and revoke any token — this is a shared operations
  console. Only the token hash is stored, so the list never exposes secrets.
  """
  use HermesWeb, :live_view

  alias Hermes.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("API Tokens"))
     |> assign(:tokens, Accounts.list_all_api_tokens())
     |> assign(:new_token, nil)
     |> assign(:show_form_modal, false)
     |> assign(:form, to_form(%{"name" => ""}))}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_token, nil)
     |> assign(:form, to_form(%{"name" => ""}))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, socket |> assign(:show_form_modal, false) |> assign(:new_token, nil)}
  end

  def handle_event("create_token", %{"name" => name}, socket) do
    # The token always belongs to the admin creating it.
    user = socket.assigns.current_user

    case Accounts.create_api_token(user, name) do
      {:ok, raw, _token} ->
        {:noreply,
         socket
         |> assign(:new_token, %{raw: raw, user: user, name: name})
         |> assign(:tokens, Accounts.list_all_api_tokens())
         |> put_flash(:info, gettext("Token created. Copy it now — it won't be shown again."))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Name is required."))}
    end
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    token = Accounts.get_api_token!(String.to_integer(id))
    {:ok, _} = Accounts.revoke_api_token(token)

    {:noreply,
     socket
     |> assign(:tokens, Accounts.list_all_api_tokens())
     |> put_flash(:info, gettext("Token revoked."))}
  end
end
