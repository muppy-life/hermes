defmodule Hermes.Kanbans do
  @moduledoc """
  The Kanbans context for organizing requests into Kanban board views.
  Note: Kanban boards are not persisted - they are dynamic views of requests.
  """

  alias Hermes.Requests
  alias Hermes.Accounts

  @doc """
  Get a list of available board views for a team.
  Each board represents a team-pair relationship.
  """
  def list_boards_by_team(team_id) do
    # Get all teams that have requests with the given team
    team = Accounts.get_team!(team_id)
    requests = Requests.list_requests_by_team(team_id)

    # Find all unique team pairs
    team_pairs =
      requests
      |> Enum.flat_map(fn request ->
        other_team_id =
          cond do
            request.requesting_team_id == team_id -> request.assigned_to_team_id
            request.assigned_to_team_id == team_id -> request.requesting_team_id
            true -> nil
          end

        if other_team_id, do: [other_team_id], else: []
      end)
      |> Enum.uniq()
      |> Enum.filter(&(&1 != nil))

    # Create board view for each team pair
    Enum.map(team_pairs, fn other_team_id ->
      other_team = Accounts.get_team!(other_team_id)

      %{
        id: "#{min(team_id, other_team_id)}_#{max(team_id, other_team_id)}",
        name: "#{team.name} ↔ #{other_team.name}",
        team_id: team_id,
        team_b_id: other_team_id,
        team: team,
        team_b: other_team
      }
    end)
  end

  @doc """
  Get a board view for a specific team pair.
  Returns a structured view with columns and requests organized by status.
  """
  def get_board!(board_id, current_user_team_id) do
    # Parse team IDs from board_id (format: "teamA_teamB")
    [team_a_str, team_b_str] = String.split(board_id, "_")
    team_a_id = String.to_integer(team_a_str)
    team_b_id = String.to_integer(team_b_str)

    team_a = Accounts.get_team!(team_a_id)
    team_b = Accounts.get_team!(team_b_id)

    # Determine which team is current user's team
    {team, team_b} = if team_a_id == current_user_team_id do
      {team_a, team_b}
    else
      {team_b, team_a}
    end

    # Get all requests between these two teams
    requests = Requests.list_requests_by_team(current_user_team_id)
    |> Enum.filter(fn request ->
      (request.requesting_team_id in [team_a_id, team_b_id]) and
      (request.assigned_to_team_id in [team_a_id, team_b_id])
    end)

    # Define columns for all status types
    columns = [
      %{id: 1, name: Gettext.gettext(HermesWeb.Gettext, "New"), position: 0, status: "new"},
      %{id: 2, name: Gettext.gettext(HermesWeb.Gettext, "Pending"), position: 1, status: "pending"},
      %{id: 3, name: Gettext.gettext(HermesWeb.Gettext, "In Progress"), position: 2, status: "in_progress"},
      %{id: 4, name: Gettext.gettext(HermesWeb.Gettext, "Review"), position: 3, status: "review"},
      %{id: 5, name: Gettext.gettext(HermesWeb.Gettext, "Blocked"), position: 4, status: "blocked"},
      %{id: 6, name: Gettext.gettext(HermesWeb.Gettext, "Completed"), position: 5, status: "completed"}
    ]

    # Organize requests into columns
    columns_with_requests = Enum.map(columns, fn column ->
      column_requests =
        requests
        |> Enum.filter(&(&1.status == column.status))
        |> Enum.sort_by(& &1.updated_at, {:desc, NaiveDateTime})

      Map.put(column, :cards, Enum.map(column_requests, fn request ->
        %{id: request.id, request: request}
      end))
    end)

    %{
      id: board_id,
      name: "#{team.name} ↔ #{team_b.name}",
      team_id: team.id,
      team_b_id: team_b.id,
      team: team,
      team_b: team_b,
      columns: columns_with_requests,
      updated_at: NaiveDateTime.utc_now()
    }
  end

  @doc """
  Update a request's status (which changes its column in the Kanban view).
  """
  def move_card(request_id, _column_id, _position) do
    # For now, we'll just return success
    # In the future, this could update the request's status based on the column
    request = Requests.get_request!(request_id)
    {:ok, request}
  end
end
