defmodule HermesWeb.DashboardLive do
  use HermesWeb, :live_view

  alias Hermes.Kanbans
  alias Hermes.Requests

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:recent_requests, get_recent_requests(current_user))
     |> assign(:boards, get_boards(current_user))
     |> assign(:stats, get_stats(current_user))
     |> assign(:roadmap, get_roadmap_data(current_user))}
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

  defp get_roadmap_data(user) do
    today = Date.utc_today()

    # Calculate date range: previous month to 6 months ahead
    start_date = today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()
    end_date = today |> Date.add(6 * 31) |> Date.end_of_month()

    # Get all requests with deadlines in range
    requests = Requests.list_requests_by_team(user.team_id)

    requests_with_deadlines =
      requests
      |> Enum.filter(fn r ->
        r.deadline != nil and
          Date.compare(r.deadline, start_date) != :lt and
          Date.compare(r.deadline, end_date) != :gt and
          r.status not in ["completed"]
      end)
      |> Enum.sort_by(& &1.deadline, Date)

    # Generate months for the roadmap (8 months: -1, current, +6)
    months = generate_months(today, -1, 6)

    # Group requests by month
    requests_by_month =
      Enum.group_by(requests_with_deadlines, fn r ->
        {r.deadline.year, r.deadline.month}
      end)

    %{
      months: months,
      requests_by_month: requests_by_month,
      today: today
    }
  end

  defp generate_months(today, months_before, months_after) do
    total_months = months_before * -1 + months_after + 1
    start_of_month = Date.beginning_of_month(today)

    Enum.map(0..(total_months - 1), fn offset ->
      date = add_months(start_of_month, months_before + offset)

      %{
        year: date.year,
        month: date.month,
        label: Calendar.strftime(date, "%b %Y"),
        short_label: Calendar.strftime(date, "%b"),
        is_current: date.year == today.year and date.month == today.month
      }
    end)
  end

  # Add months to a date using proper month arithmetic
  defp add_months(date, months_to_add) do
    # Calculate the new month and year
    total_months = date.year * 12 + date.month - 1 + months_to_add
    new_year = div(total_months, 12)
    new_month = rem(total_months, 12) + 1

    # Ensure the day is valid for the new month
    new_day = min(date.day, Date.days_in_month(%Date{year: new_year, month: new_month, day: 1}))

    Date.new!(new_year, new_month, new_day)
  end

  # Helper function to calculate today marker position as percentage
  def calculate_today_position(months, today) do
    month_index =
      Enum.find_index(months, fn m ->
        m.year == today.year and m.month == today.month
      end)

    case month_index do
      nil ->
        nil

      idx ->
        # Calculate position within the month (0-1)
        days_in_month = Date.days_in_month(today)
        day_position = (today.day - 1) / days_in_month

        # Each month takes 12.5% (100/8), position within that column
        month_width = 100 / 8
        idx * month_width + day_position * month_width
    end
  end

  # Helper function to get background class based on priority
  def priority_bg_class(priority) do
    case priority do
      1 -> "bg-yellow-100 text-yellow-900"
      2 -> "bg-orange-100 text-orange-900"
      3 -> "bg-red-100 text-red-900"
      4 -> "bg-red-200 text-red-900"
      _ -> "bg-base-200"
    end
  end
end
