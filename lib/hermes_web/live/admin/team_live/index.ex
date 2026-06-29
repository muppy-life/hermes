defmodule HermesWeb.Admin.TeamLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Accounts.Team

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Teams"))
     |> assign(:show_form_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:selected_team, nil)
     |> assign(:form_mode, :new)
     |> assign(:form, to_form(%{}))
     |> load_teams()}
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    changeset = Team.changeset(%Team{}, %{})

    {:noreply,
     socket
     |> assign(:form_mode, :new)
     |> assign(:selected_team, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    team = Accounts.get_team!(String.to_integer(id))
    changeset = Team.changeset(team, %{})

    {:noreply,
     socket
     |> assign(:form_mode, :edit)
     |> assign(:selected_team, team)
     |> assign(:form, to_form(changeset))
     |> assign(:show_form_modal, true)}
  end

  def handle_event("close_form_modal", _params, socket) do
    {:noreply, assign(socket, :show_form_modal, false)}
  end

  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    team = Accounts.get_team!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_team, team)
     |> assign(:show_delete_modal, true)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("validate", %{"team" => team_params}, socket) do
    team = socket.assigns.selected_team || %Team{}
    changeset = Team.changeset(team, team_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"team" => team_params}, socket) do
    save_team(socket, socket.assigns.form_mode, team_params)
  end

  def handle_event("confirm_delete", _params, socket) do
    team = socket.assigns.selected_team
    # Re-read the count at delete time so a concurrent reassignment can't slip
    # past the guard with a stale value from mount.
    member_count = Accounts.count_team_members(team.id)

    if member_count > 0 do
      {:noreply,
       socket
       |> assign(:show_delete_modal, false)
       |> put_flash(
         :error,
         gettext("Cannot delete a team that still has members. Reassign them first.")
       )}
    else
      do_delete_team(socket, team)
    end
  end

  defp do_delete_team(socket, team) do
    case Accounts.delete_team(team) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_teams()
         |> assign(:show_delete_modal, false)
         |> put_flash(:info, gettext("Team deleted successfully"))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:show_delete_modal, false)
         |> put_flash(:error, gettext("Failed to delete team"))}
    end
  end

  defp save_team(socket, :new, team_params) do
    case Accounts.create_team(team_params) do
      {:ok, _team} ->
        {:noreply,
         socket
         |> load_teams()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Team created successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp save_team(socket, :edit, team_params) do
    team = socket.assigns.selected_team

    case Accounts.update_team(team, team_params) do
      {:ok, _team} ->
        {:noreply,
         socket
         |> load_teams()
         |> assign(:show_form_modal, false)
         |> put_flash(:info, gettext("Team updated successfully"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp load_teams(socket) do
    teams = Accounts.list_teams()
    member_counts = Accounts.count_users_by_team()

    socket
    |> stream(:teams, teams, reset: true)
    |> assign(:team_count, length(teams))
    |> assign(:member_counts, member_counts)
  end
end
