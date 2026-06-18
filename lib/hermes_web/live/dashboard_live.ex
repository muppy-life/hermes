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
     |> assign(:roadmap_offset, 0)
     |> assign(:roadmap, get_roadmap_data(current_user, 0))
     |> assign(:show_new_request, false)}
  end

  @impl true
  def handle_event("show_new_request", _params, socket) do
    {:noreply, assign(socket, :show_new_request, true)}
  end

  def handle_event("roadmap_prev", _params, socket) do
    {:noreply, shift_roadmap(socket, -1)}
  end

  def handle_event("roadmap_next", _params, socket) do
    {:noreply, shift_roadmap(socket, 1)}
  end

  defp shift_roadmap(socket, delta) do
    offset = socket.assigns.roadmap_offset + delta
    user = socket.assigns[:current_user]

    socket
    |> assign(:roadmap_offset, offset)
    |> assign(:roadmap, get_roadmap_data(user, offset))
  end

  @impl true
  def handle_info(:hide_new_request, socket) do
    {:noreply, assign(socket, :show_new_request, false)}
  end

  def handle_info({:new_request_created, _request}, socket) do
    current_user = socket.assigns[:current_user]

    {:noreply,
     socket
     |> put_flash(:info, gettext("Request created successfully"))
     |> assign(:recent_requests, get_recent_requests(current_user))
     |> assign(:stats, get_stats(current_user))}
  end

  def handle_info({:new_request_flash, kind, msg}, socket) do
    {:noreply, put_flash(socket, kind, msg)}
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
        need_requirement: Enum.count(requests, &(&1.status == "need_requirement")),
        pending: Enum.count(requests, &(&1.status == "pending")),
        future_planning: Enum.count(requests, &(&1.status == "future_planning")),
        todo_in_sprint: Enum.count(requests, &(&1.status == "todo_in_sprint")),
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
    requests =
      Requests.list_requests_by_team(user.team_id)
      |> Enum.reject(&(&1.status == "discarded"))

    %{
      total_requests: length(requests),
      new: Enum.count(requests, &(&1.status == "new")),
      need_requirement: Enum.count(requests, &(&1.status == "need_requirement")),
      pending: Enum.count(requests, &(&1.status == "pending")),
      future_planning: Enum.count(requests, &(&1.status == "future_planning")),
      todo_in_sprint: Enum.count(requests, &(&1.status == "todo_in_sprint")),
      in_progress: Enum.count(requests, &(&1.status == "in_progress")),
      review: Enum.count(requests, &(&1.status == "review")),
      completed: Enum.count(requests, &(&1.status == "completed")),
      blocked: Enum.count(requests, &(&1.status == "blocked"))
    }
  end

  # Number of months visible in the roadmap window (current + 2 ahead by default).
  @roadmap_window 3

  defp get_roadmap_data(user, offset) do
    today = Date.utc_today()

    # Visible window: current month shifted by `offset`, spanning @roadmap_window months.
    window_start = today |> Date.beginning_of_month() |> Date.shift(month: offset)
    window_end = window_start |> Date.shift(month: @roadmap_window - 1) |> Date.end_of_month()

    # Get all team requests with deadlines inside the visible window.
    requests = Requests.list_requests_by_team(user.team_id)

    requests_with_deadlines =
      requests
      |> Enum.filter(fn r ->
        r.deadline != nil and
          Date.compare(r.deadline, window_start) != :lt and
          Date.compare(r.deadline, window_end) != :gt and
          r.status != "completed" and r.status != "discarded"
      end)
      |> Enum.sort_by(& &1.deadline, Date)

    months = generate_months(today, window_start, @roadmap_window)

    requests_by_month =
      Enum.group_by(requests_with_deadlines, fn r ->
        {r.deadline.year, r.deadline.month}
      end)

    boards =
      requests_with_deadlines
      |> Enum.map(&rm_board_label/1)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      months: months,
      requests_by_month: requests_by_month,
      boards: boards,
      today: today
    }
  end

  defp generate_months(today, window_start, count) do
    Enum.map(0..(count - 1), fn idx ->
      date = Date.shift(window_start, month: idx)

      %{
        year: date.year,
        month: date.month,
        label: Calendar.strftime(date, "%b %Y"),
        short_label: Calendar.strftime(date, "%b"),
        is_current: date.year == today.year and date.month == today.month
      }
    end)
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

  # --- Roadmap task-card helpers (new design) ---

  @doc "Roadmap task card tint class by priority."
  def rm_prio_class(priority) when priority in [3, 4], do: "prio-alta"
  def rm_prio_class(2), do: "prio-media"
  def rm_prio_class(_), do: "prio-baja"

  @doc "Status ring class for a roadmap task dot."
  def rm_status_class(status) do
    case status do
      "in_progress" -> "s-progress"
      "review" -> "s-review"
      "completed" -> "s-done"
      "blocked" -> "s-blocked"
      _ -> "s-pending"
    end
  end

  @doc "Priority tag class + short label (P0/P1/P2)."
  def rm_priority_tag(priority) when priority in [3, 4], do: {"tag-p0", "P0"}
  def rm_priority_tag(2), do: {"tag-p1", "P1"}
  def rm_priority_tag(_), do: {"tag-p2", "P2"}

  @doc "Initials from an email address."
  def rm_initials(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  def rm_initials(_), do: "?"

  @doc "Whether a deadline is overdue (past, not today)."
  def rm_overdue?(date), do: Date.diff(date, Date.utc_today()) < 0

  @doc "Week-of-month bucket (1..4) for a date, used to spread roadmap cards across week columns."
  def week_of_month(%Date{day: day}), do: min(div(day - 1, 7) + 1, 4)

  @doc "Statuses that can appear on the roadmap (completed/discarded are filtered out)."
  def rm_statuses do
    ~w(new need_requirement pending future_planning todo_in_sprint in_progress review blocked)
  end

  @doc "Board label for a request — the team pair that owns the kanban board."
  def rm_board_label(req) do
    requesting = req.requesting_team && req.requesting_team.name
    assigned = req.assigned_to_team && req.assigned_to_team.name

    cond do
      requesting && assigned -> "#{requesting} ↔ #{assigned}"
      requesting -> requesting
      assigned -> assigned
      true -> gettext("Unassigned")
    end
  end

  @doc "Deterministic hue (0..359) for a board label, used to tint its cards consistently."
  def rm_board_hue(label), do: rem(:erlang.phash2(label), 360)

  @doc "Inline border/background style tinting a card by its board."
  def rm_board_style(label) do
    hue = rm_board_hue(label)
    "border-color: hsl(#{hue} 50% 62%); background: hsl(#{hue} 60% 97%);"
  end

  @doc "Swatch color for a board legend entry."
  def rm_board_swatch(label), do: "hsl(#{rm_board_hue(label)} 50% 62%)"

  @doc "Human-readable status label for roadmap tooltips."
  def rm_status_label(status) do
    case status do
      "new" -> gettext("New")
      "need_requirement" -> gettext("Need requirement")
      "pending" -> gettext("Pending")
      "future_planning" -> gettext("Future Planning")
      "todo_in_sprint" -> gettext("Todo in Sprint")
      "in_progress" -> gettext("In Progress")
      "review" -> gettext("Review")
      "completed" -> gettext("Completed")
      "blocked" -> gettext("Blocked")
      other -> other
    end
  end

  @doc "Priority tooltip text for roadmap pills."
  def rm_priority_title(priority) do
    label =
      case priority do
        1 -> gettext("Low")
        2 -> gettext("Normal")
        3 -> gettext("Important")
        4 -> gettext("Critical")
        _ -> gettext("Unknown")
      end

    gettext("Priority: %{label}", label: label)
  end

  @doc "Deadline tooltip text for roadmap pills."
  def rm_deadline_title(date) do
    days = Date.diff(date, Date.utc_today())
    formatted = Calendar.strftime(date, "%d %b %Y")

    cond do
      days < 0 -> gettext("Deadline %{date} · overdue", date: formatted)
      days == 0 -> gettext("Deadline %{date} · due today", date: formatted)
      days <= 7 -> gettext("Deadline %{date} · due soon", date: formatted)
      true -> gettext("Deadline %{date}", date: formatted)
    end
  end

  @doc "Deadline pill class + label."
  def rm_deadline(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days < 0 -> {"overdue", gettext("Overdue")}
      days == 0 -> {"overdue", gettext("Today")}
      days <= 7 -> {"soon", "D#{date.day}"}
      true -> {"", "D#{date.day}"}
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

  def roadmap_status_icon(%{status: "need_requirement"} = assigns) do
    ~H"""
    <span class="text-orange-600" title={gettext("Need requirement")}>
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
          d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
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

  def roadmap_status_icon(%{status: "future_planning"} = assigns) do
    ~H"""
    <span class="text-teal-600" title={gettext("Future Planning")}>
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

  def roadmap_status_icon(%{status: "todo_in_sprint"} = assigns) do
    ~H"""
    <span class="text-sky-600" title={gettext("Todo in Sprint")}>
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
          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
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
