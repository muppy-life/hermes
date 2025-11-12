defmodule HermesWeb.DashboardLive do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Kanbans

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:recent_requests, get_recent_requests(current_user))
     |> assign(:boards, get_boards(current_user))
     |> assign(:stats, get_stats(current_user))}
  end

  defp get_recent_requests(user) do
    Requests.list_requests_by_team(user.team_id) |> Enum.take(5)
  end

  defp get_boards(user) do
    boards = Kanbans.list_boards_by_team(user.team_id)

    # Add stats for each board
    Enum.map(boards, fn board ->
      # Get the board with all its requests to calculate stats
      full_board = Kanbans.get_board!(board.id, user.team_id)

      # Extract all requests from all columns
      requests =
        full_board.columns
        |> Enum.flat_map(& &1.cards)
        |> Enum.map(& &1.request)

      stats = %{
        total: length(requests),
        new: Enum.count(requests, &(&1.status == "new")),
        pending: Enum.count(requests, &(&1.status == "pending")),
        in_progress: Enum.count(requests, &(&1.status == "in_progress")),
        review: Enum.count(requests, &(&1.status == "review")),
        completed: Enum.count(requests, &(&1.status == "completed")),
        blocked: Enum.count(requests, &(&1.status == "blocked"))
      }

      board
      |> Map.put(:task_stats, stats)
      |> Map.put(:updated_at, NaiveDateTime.utc_now())
    end)
  end

  defp get_stats(user) do
    requests = Requests.list_requests_by_team(user.team_id)

    %{
      total_requests: length(requests),
      new: Enum.count(requests, &(&1.status == "new")),
      pending: Enum.count(requests, &(&1.status == "pending")),
      in_progress: Enum.count(requests, &(&1.status == "in_progress")),
      review: Enum.count(requests, &(&1.status == "review")),
      completed: Enum.count(requests, &(&1.status == "completed")),
      blocked: Enum.count(requests, &(&1.status == "blocked"))
    }
  end
end
