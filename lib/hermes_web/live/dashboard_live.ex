defmodule HermesWeb.DashboardLive do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Kanbans
  alias Hermes.Accounts

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
    if Accounts.is_dev_team?(user) do
      Requests.list_requests() |> Enum.take(5)
    else
      Requests.list_requests_by_team(user.team_id) |> Enum.take(5)
    end
  end

  defp get_boards(user) do
    boards = if Accounts.is_dev_team?(user) do
      Kanbans.list_boards()
    else
      Kanbans.list_boards_by_team(user.team_id)
    end

    # Preload columns with cards and their requests to calculate stats
    boards
    |> Hermes.Repo.preload([columns: [cards: :request]])
    |> Enum.map(&add_board_stats/1)
  end

  defp add_board_stats(board) do
    # Get all requests from all cards in all columns
    requests =
      board.columns
      |> Enum.flat_map(& &1.cards)
      |> Enum.map(& &1.request)
      |> Enum.filter(& &1 != nil)

    stats = %{
      total: length(requests),
      pending: Enum.count(requests, &(&1.status == "pending")),
      in_progress: Enum.count(requests, &(&1.status == "in_progress")),
      completed: Enum.count(requests, &(&1.status == "completed")),
      blocked: Enum.count(requests, &(&1.status == "blocked"))
    }

    Map.put(board, :task_stats, stats)
  end

  defp get_stats(user) do
    requests =
      if Accounts.is_dev_team?(user) do
        Requests.list_requests()
      else
        Requests.list_requests_by_team(user.team_id)
      end

    %{
      total_requests: length(requests),
      pending: Enum.count(requests, &(&1.status == "pending")),
      in_progress: Enum.count(requests, &(&1.status == "in_progress")),
      completed: Enum.count(requests, &(&1.status == "completed")),
      blocked: Enum.count(requests, &(&1.status == "blocked"))
    }
  end
end
