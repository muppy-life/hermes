defmodule HermesWeb.KanbanLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Kanbans
  alias Hermes.Requests

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    team_ids = Accounts.team_ids(current_user)
    all_requests = Requests.list_requests_by_teams(team_ids)
    teams_by_id = Map.new(Accounts.list_teams(), &{&1.id, &1})

    {:ok,
     socket
     |> assign(:boards, list_boards_with_stats(team_ids, all_requests))
     |> assign(:my_board_stats, request_stats(all_requests))
     |> assign(:my_teams, Enum.map(team_ids, &Map.fetch!(teams_by_id, &1)))
     |> assign(:page_title, "Kanban Boards")}
  end

  defp list_boards_with_stats(team_ids, all_requests) do
    team_ids
    |> Kanbans.list_boards_by_teams()
    |> Enum.map(fn board ->
      stats = calculate_board_stats(board, all_requests)
      Map.put(board, :stats, stats)
    end)
  end

  defp calculate_board_stats(board, all_requests) do
    # Filter requests for this specific board (team pair)
    # For cross-team boards, exclude same-team requests to prevent them from leaking into the wrong board
    cross_team_board? = board.team_id != board.team_b_id

    all_requests
    |> Enum.filter(fn request ->
      team_ids = [board.team_id, board.team_b_id]

      request.requesting_team_id in team_ids and
        request.assigned_to_team_id in team_ids and
        (not cross_team_board? or request.requesting_team_id != request.assigned_to_team_id)
    end)
    |> request_stats()
  end

  defp request_stats(requests) do
    # Count by status
    status_counts =
      requests
      |> Enum.group_by(& &1.status)
      |> Enum.map(fn {status, reqs} -> {status, length(reqs)} end)
      |> Map.new()

    %{
      total: length(requests),
      new:
        Map.get(status_counts, "new", 0) + Map.get(status_counts, "need_requirement", 0) +
          Map.get(status_counts, "pending", 0) + Map.get(status_counts, "future_planning", 0) +
          Map.get(status_counts, "todo_in_sprint", 0),
      in_progress: Map.get(status_counts, "in_progress", 0),
      completed: Map.get(status_counts, "completed", 0)
    }
  end
end
