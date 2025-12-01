defmodule HermesWeb.KanbanLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Kanbans
  alias Hermes.Requests

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:boards, list_boards_with_stats(socket))
     |> assign(:page_title, "Kanban Boards")}
  end

  defp list_boards_with_stats(socket) do
    current_user = socket.assigns[:current_user]
    boards = Kanbans.list_boards_by_team(current_user.team_id)

    # Get all requests once
    all_requests = Requests.list_requests_by_team(current_user.team_id)

    Enum.map(boards, fn board ->
      stats = calculate_board_stats(board, all_requests)
      Map.put(board, :stats, stats)
    end)
  end

  defp calculate_board_stats(board, all_requests) do
    # Filter requests for this specific board (team pair)
    board_requests =
      all_requests
      |> Enum.filter(fn request ->
        team_ids = [board.team_id, board.team_b_id]
        request.requesting_team_id in team_ids and request.assigned_to_team_id in team_ids
      end)

    # Count by status
    status_counts =
      board_requests
      |> Enum.group_by(& &1.status)
      |> Enum.map(fn {status, reqs} -> {status, length(reqs)} end)
      |> Map.new()

    %{
      total: length(board_requests),
      new: Map.get(status_counts, "new", 0) + Map.get(status_counts, "pending", 0),
      in_progress: Map.get(status_counts, "in_progress", 0),
      completed: Map.get(status_counts, "completed", 0)
    }
  end
end
