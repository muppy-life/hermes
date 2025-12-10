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
    end_date = today |> Date.shift(month: 6) |> Date.end_of_month()

    # Get all requests with deadlines in range
    requests = Requests.list_requests_by_team(user.team_id)

    requests_with_deadlines =
      requests
      |> Enum.filter(fn r ->
        r.deadline != nil and
          Date.compare(r.deadline, start_date) != :lt and
          Date.compare(r.deadline, end_date) != :gt and
          r.status != "completed"
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
    start_month = Date.beginning_of_month(today) |> Date.shift(month: months_before)

    Enum.map(0..(months_before * -1 + months_after), fn offset ->
      date = Date.shift(start_month, month: offset)

      %{
        year: date.year,
        month: date.month,
        label: Calendar.strftime(date, "%b %Y"),
        short_label: Calendar.strftime(date, "%b"),
        is_current: date.year == today.year and date.month == today.month
      }
    end)
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

  # Status icon component for roadmap cards
  attr :status, :string, required: true

  def roadmap_status_icon(%{status: "new"} = assigns) do
    ~H"""
    <span class="text-cyan-600" title={gettext("New")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(%{status: "pending"} = assigns) do
    ~H"""
    <span class="text-yellow-600" title={gettext("Pending")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(%{status: "in_progress"} = assigns) do
    ~H"""
    <span class="text-purple-600" title={gettext("In Progress")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M13 10V3L4 14h7v7l9-11h-7z"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(%{status: "review"} = assigns) do
    ~H"""
    <span class="text-indigo-600" title={gettext("Review")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
        />
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(%{status: "completed"} = assigns) do
    ~H"""
    <span class="text-green-600" title={gettext("Completed")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(%{status: "blocked"} = assigns) do
    ~H"""
    <span class="text-red-600" title={gettext("Blocked")}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
        />
      </svg>
    </span>
    """
  end

  def roadmap_status_icon(assigns) do
    ~H"""
    <span class="text-base-content/50" title={@status}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </span>
    """
  end
end
