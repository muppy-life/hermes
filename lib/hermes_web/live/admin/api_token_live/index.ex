defmodule HermesWeb.Admin.ApiTokenLive.Index do
  @moduledoc """
  Admin-only management of API tokens used for REST/MCP access. Admins mint a
  token for a tech-team user; the raw token is shown once and never again.
  """
  use HermesWeb, :live_view

  alias Hermes.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("API Tokens"))
     |> assign(:tokens, Accounts.list_all_api_tokens())
     |> assign(:tech_users, tech_users())
     |> assign(:new_token, nil)
     |> assign(:show_form_modal, false)
     |> assign(:form, to_form(%{"name" => "", "user_id" => nil}))}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_token, nil)
     |> assign(:form, to_form(%{"name" => "", "user_id" => nil}))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, socket |> assign(:show_form_modal, false) |> assign(:new_token, nil)}
  end

  def handle_event("create_token", %{"name" => name, "user_id" => user_id}, socket) do
    with {:ok, user_id} <- parse_user_id(user_id),
         user when not is_nil(user) <- Accounts.get_active_user(user_id),
         true <- Accounts.is_dev_team?(user),
         {:ok, raw, _token} <- Accounts.create_api_token(user, name) do
      {:noreply,
       socket
       |> assign(:new_token, %{raw: raw, user: user, name: name})
       |> assign(:tokens, Accounts.list_all_api_tokens())
       |> put_flash(:info, gettext("Token created. Copy it now — it won't be shown again."))}
    else
      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Name is required."))}

      false ->
        {:noreply, put_flash(socket, :error, gettext("Selected user is not on the tech team."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Please select a user and enter a name."))}
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

  defp parse_user_id(nil), do: :error
  defp parse_user_id(""), do: :error

  defp parse_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  # Only tech-team members (dev_team or admins) can hold API tokens, matching
  # the access the tokens grant.
  defp tech_users do
    Accounts.list_users()
    |> Enum.filter(&Accounts.is_dev_team?/1)
    |> Enum.sort_by(&Hermes.Accounts.User.display_name/1)
  end
end
