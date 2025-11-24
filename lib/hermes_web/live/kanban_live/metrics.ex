defmodule HermesWeb.KanbanLive.Metrics do
  use HermesWeb, :live_view

  alias Hermes.Repo
  alias Hermes.Requests.Request
  import Ecto.Query

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    current_user = socket.assigns[:current_user]
    board = Hermes.Kanbans.get_board!(board_id, current_user.team_id)

    {:ok,
     socket
     |> assign(:page_title, "#{board.name} - Metrics")
     |> assign(:current_user, current_user)
     |> assign(:board, board)
     |> assign(:board_id, board_id)
     |> load_metrics()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_metrics(socket) do
    board = socket.assigns[:board]

    # Get all request IDs from the board's cards
    request_ids = get_board_request_ids(board)

    # Get all requests in this board
    requests = get_requests_by_ids(request_ids)

    socket
    |> assign(:total_requests, length(requests))
    |> assign(:priority_distribution, calculate_priority_distribution(requests))
    |> assign(:kind_distribution, calculate_kind_distribution(requests))
    |> assign(:status_distribution, calculate_status_distribution(requests))
    |> assign(:user_contributions, calculate_user_contributions(request_ids))
    |> assign(:avg_time_to_complete, calculate_avg_time_to_complete(request_ids))
    |> assign(:time_by_priority, calculate_time_by_priority(request_ids))
    |> assign(:recent_completions, get_recent_completions(request_ids))
  end

  defp get_board_request_ids(board) do
    board.columns
    |> Enum.flat_map(fn column -> column.cards end)
    |> Enum.map(fn card ->
      if card.request do
        card.request.id
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_requests_by_ids(request_ids) do
    from(r in Request,
      where: r.id in ^request_ids,
      preload: [:requesting_team, :assigned_to_team, :created_by]
    )
    |> Repo.all()
  end

  defp calculate_priority_distribution(requests) do
    requests
    |> Enum.group_by(& &1.priority)
    |> Enum.map(fn {priority, reqs} ->
      %{
        priority: priority,
        label: Request.priority_label(priority),
        count: length(reqs),
        percentage: Float.round(length(reqs) / max(length(requests), 1) * 100, 1)
      }
    end)
    |> Enum.sort_by(& &1.priority, :desc)
  end

  defp calculate_kind_distribution(requests) do
    requests
    |> Enum.group_by(& &1.kind)
    |> Enum.map(fn {kind, reqs} ->
      %{
        kind: kind,
        label: if(kind, do: Request.kind_label(kind), else: "Unknown"),
        count: length(reqs),
        percentage: Float.round(length(reqs) / max(length(requests), 1) * 100, 1)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp calculate_status_distribution(requests) do
    requests
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, reqs} ->
      %{
        status: status,
        count: length(reqs),
        percentage: Float.round(length(reqs) / max(length(requests), 1) * 100, 1)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp calculate_user_contributions(request_ids) do
    from(r in Request,
      join: u in assoc(r, :created_by),
      where: r.id in ^request_ids,
      group_by: [u.id, u.email],
      select: %{
        user_id: u.id,
        user_email: u.email,
        count: count(r.id)
      },
      order_by: [desc: count(r.id)]
    )
    |> Repo.all()
    |> Enum.take(10)
  end

  defp calculate_avg_time_to_complete(request_ids) do
    completed_requests =
      from(r in Request,
        where:
          r.id in ^request_ids and r.status == "completed" and not is_nil(r.updated_at) and
            not is_nil(r.inserted_at),
        select: %{
          inserted_at: r.inserted_at,
          updated_at: r.updated_at
        }
      )
      |> Repo.all()

    if length(completed_requests) > 0 do
      total_seconds =
        Enum.reduce(completed_requests, 0, fn req, acc ->
          acc + DateTime.diff(req.updated_at, req.inserted_at, :second)
        end)

      avg_seconds = div(total_seconds, length(completed_requests))
      format_duration(avg_seconds)
    else
      "N/A"
    end
  end

  defp calculate_time_by_priority(request_ids) do
    from(r in Request,
      where:
        r.id in ^request_ids and r.status == "completed" and not is_nil(r.updated_at) and
          not is_nil(r.inserted_at),
      select: %{
        priority: r.priority,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.priority)
    |> Enum.map(fn {priority, requests} ->
      total_seconds =
        Enum.reduce(requests, 0, fn req, acc ->
          acc + DateTime.diff(req.updated_at, req.inserted_at, :second)
        end)

      avg_seconds = if length(requests) > 0, do: div(total_seconds, length(requests)), else: 0

      %{
        priority: priority,
        label: Request.priority_label(priority),
        avg_time: format_duration(avg_seconds),
        count: length(requests)
      }
    end)
    |> Enum.sort_by(& &1.priority, :desc)
  end

  defp get_recent_completions(request_ids) do
    from(r in Request,
      where: r.id in ^request_ids and r.status == "completed",
      order_by: [desc: r.updated_at],
      limit: 10,
      preload: [:requesting_team, :assigned_to_team, :created_by]
    )
    |> Repo.all()
    |> Enum.map(fn req ->
      duration = DateTime.diff(req.updated_at, req.inserted_at, :second)
      Map.put(req, :completion_time, format_duration(duration))
    end)
  end

  defp format_duration(seconds) do
    cond do
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{Float.round(seconds / 3600, 1)}h"
      true -> "#{Float.round(seconds / 86_400, 1)}d"
    end
  end
end
