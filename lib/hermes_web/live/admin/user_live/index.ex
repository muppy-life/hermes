defmodule HermesWeb.Admin.UserLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:users, list_users())
     |> assign(:teams, Accounts.list_teams())
     |> assign(:show_form_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:selected_user, nil)
     |> assign(:form_mode, :new)
     |> assign(:form, to_form(%{}))}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    changeset = User.changeset(%User{}, %{})

    {:noreply,
     socket
     |> assign(:form_mode, :new)
     |> assign(:selected_user, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    user = Accounts.get_user!(String.to_integer(id))
    changeset = User.changeset(user, %{})

    {:noreply,
     socket
     |> assign(:form_mode, :edit)
     |> assign(:selected_user, user)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, assign(socket, :show_form_modal, false)}
  end

  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    user = Accounts.get_user!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:show_delete_modal, true)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    user = socket.assigns.selected_user || %User{}
    changeset = User.changeset(user, user_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.form_mode, user_params)
  end

  def handle_event("confirm_delete", _params, socket) do
    user = socket.assigns.selected_user

    case Accounts.delete_user(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:users, list_users())
         |> assign(:show_delete_modal, false)
         |> put_flash(:info, "User deleted successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete user")}
    end
  end

  defp save_user(socket, :new, user_params) do
    # Hash the password before creating
    user_params_with_hash = hash_password(user_params)

    case Accounts.create_user(user_params_with_hash) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, list_users())
         |> assign(:show_form_modal, false)
         |> put_flash(:info, "User created successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp save_user(socket, :edit, user_params) do
    user = socket.assigns.selected_user

    # Only hash password if it's being changed
    user_params_final =
      if user_params["password"] && user_params["password"] != "" do
        hash_password(user_params)
      else
        Map.delete(user_params, "password")
      end

    case Accounts.update_user(user, user_params_final) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, list_users())
         |> assign(:show_form_modal, false)
         |> put_flash(:info, "User updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp hash_password(user_params) do
    password = user_params["password"] || ""
    hashed_password = :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
    Map.put(user_params, "hashed_password", hashed_password)
  end

  defp list_users do
    Accounts.list_users()
  end

  defp humanize_role("team_member"), do: "Team Member"
  defp humanize_role("dev_team"), do: "Developer"
  defp humanize_role("product_owner"), do: "Product Owner"
  defp humanize_role("admin"), do: "Admin"
  defp humanize_role(_), do: "Unknown"
end
