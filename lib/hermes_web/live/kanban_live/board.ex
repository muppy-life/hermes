defmodule HermesWeb.KanbanLive.Board do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Kanbans
  alias Hermes.Requests
  alias HermesWeb.NavigationHistory

  @page_size 10

  @doc "Number of cards rendered per column before scroll pagination kicks in."
  def page_size, do: @page_size

  @doc "Status dot color for a kanban column header."
  def kanban_dot_color("new"), do: "#94a3b8"
  def kanban_dot_color("need_requirement"), do: "#94a3b8"
  def kanban_dot_color("pending"), do: "#94a3b8"
  def kanban_dot_color("future_planning"), do: "#94a3b8"
  def kanban_dot_color("todo_in_sprint"), do: "#7dd3fc"
  def kanban_dot_color("in_progress"), do: "#64748b"
  def kanban_dot_color("review"), do: "#94a3b8"
  def kanban_dot_color("completed"), do: "#4ade80"
  def kanban_dot_color("blocked"), do: "#f87171"
  def kanban_dot_color(_), do: "#94a3b8"

  @doc "Status ring class for the small circle on a kanban card."
  def kanban_status_class(status) do
    case status do
      "in_progress" -> "s-progress"
      "review" -> "s-review"
      "completed" -> "s-done"
      "blocked" -> "s-blocked"
      _ -> "s-pending"
    end
  end

  @doc "Priority tag class + label (P0/P1/P2)."
  def priority_tag(4), do: {"tag-p0", "P0"}
  def priority_tag(3), do: {"tag-p0", "P0"}
  def priority_tag(2), do: {"tag-p1", "P1"}
  def priority_tag(1), do: {"tag-p2", "P2"}
  def priority_tag(_), do: {"tag-p2", "P2"}

  @doc "Initials from a user's name (email fallback)."
  def initials(user), do: Hermes.Accounts.User.initials(user)

  @doc "Deadline pill class given days remaining (nil if no deadline)."
  def deadline_class(nil), do: nil

  def deadline_class(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days < 0 -> "overdue"
      days == 0 -> "overdue"
      days <= 7 -> "soon"
      true -> ""
    end
  end

  def deadline_label(nil), do: nil

  def deadline_label(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days < 0 -> gettext("Overdue")
      days == 0 -> gettext("Today")
      true -> Calendar.strftime(date, "%b %d")
    end
  end

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :mine}} = socket) do
    team_ids = Accounts.team_ids(socket.assigns.current_user)
    teams = Accounts.list_teams()
    teams_by_id = Map.new(teams, &{&1.id, &1})

    {:ok,
     socket
     |> NavigationHistory.assign_return_path(default: ~p"/boards")
     |> assign(:team_ids, team_ids)
     |> assign(:my_teams, Enum.map(team_ids, &Map.fetch!(teams_by_id, &1)))
     |> assign(:page_title, gettext("My board"))
     |> assign(:teams, teams)
     |> assign(:show_new_request, false)}
  end

  def mount(%{"id" => board_id}, _session, socket) do
    current_user = socket.assigns[:current_user]
    team_ids = Accounts.team_ids(current_user)
    board = Kanbans.get_board!(board_id, team_ids)

    if can_access_board?(current_user, board) do
      {:ok,
       socket
       |> NavigationHistory.assign_return_path(default: ~p"/boards")
       |> assign(:team_ids, team_ids)
       |> assign(:raw_board_id, board_id)
       |> assign(:page_title, board.name)
       |> assign(:teams, Accounts.list_teams())
       |> assign(:show_new_request, false)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access this board")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter_perspective = safe_to_atom(params["perspective"], :all)
    filter_priority = params["priority"] || "all"
    filter_team = params["team"] || "all"
    filter_search = params["search"] || ""

    socket = assign_selected_teams(socket, params["teams"])
    board = load_board(socket)

    filtered_board =
      apply_all_filters(
        board,
        filter_perspective,
        filter_priority,
        filter_team,
        filter_search
      )

    total_count = count_all_cards(filtered_board)

    {:noreply,
     socket
     |> assign(:board, filtered_board)
     |> assign(:filter_perspective, filter_perspective)
     |> assign(:filter_priority, filter_priority)
     |> assign(:filter_team, filter_team)
     |> assign(:filter_search, filter_search)
     |> assign(
       :search_form,
       to_form(%{
         "search" => filter_search,
         "priority" => filter_priority,
         "team" => filter_team
       })
     )
     |> assign(:total_count, total_count)
     |> reset_limits(filtered_board)}
  end

  # One visible-card limit per column, so scrolling one column doesn't expand the others.
  defp reset_limits(socket, board) do
    limits = Map.new(board.columns, &{&1.id, @page_size})
    assign(socket, :limits, limits)
  end

  defp safe_to_atom(nil, default), do: default

  defp safe_to_atom(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end

  defp safe_to_atom(_, default), do: default

  @impl true
  def handle_event(
        "move_card",
        %{
          "card_id" => card_id,
          "column_id" => _column_id,
          "position" => _position,
          "new_status" => new_status
        },
        socket
      ) do
    request_id = String.to_integer(card_id)
    current_user = socket.assigns[:current_user]

    # Get the request and update its status
    request = Requests.get_request!(request_id)

    case Requests.update_request(request, %{status: new_status}, current_user.id) do
      {:ok, _updated_request} ->
        # Reload the board with updated data
        board = load_board(socket)

        filtered_board =
          apply_all_filters(
            board,
            socket.assigns.filter_perspective,
            socket.assigns.filter_priority,
            socket.assigns.filter_team,
            socket.assigns.filter_search
          )

        total_count = count_all_cards(filtered_board)
        {:noreply, socket |> assign(:board, filtered_board) |> assign(:total_count, total_count)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move card")}
    end
  end

  def handle_event("set_filter", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket, to: board_path(socket, build_params(socket, perspective: filter)))}
  end

  def handle_event("apply_filters", %{"priority" => priority, "team" => team} = params, socket) do
    search = Map.get(params, "search", socket.assigns.filter_search)

    {:noreply,
     push_patch(socket,
       to:
         board_path(socket, build_params(socket, priority: priority, team: team, search: search))
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: board_path(socket, build_params(socket, priority: "all", team: "all", search: ""))
     )}
  end

  # My board team chips. The last selected team can't be turned off, so the
  # board never ends up empty by accident.
  def handle_event("toggle_team", %{"team-id" => team_id}, socket) do
    team_id = String.to_integer(team_id)
    %{team_ids: team_ids, selected_team_ids: selected_ids} = socket.assigns

    selected_ids =
      if team_id in selected_ids,
        do: List.delete(selected_ids, team_id),
        else: [team_id | selected_ids]

    case Enum.filter(team_ids, &(&1 in selected_ids)) do
      [] ->
        {:noreply, socket}

      ^team_ids ->
        {:noreply, push_patch(socket, to: board_path(socket, build_params(socket, teams: "")))}

      ids ->
        {:noreply,
         push_patch(socket,
           to: board_path(socket, build_params(socket, teams: Enum.join(ids, ",")))
         )}
    end
  end

  def handle_event("load_more", %{"column_id" => column_id}, socket) do
    column_id = String.to_integer(column_id)

    limits =
      Map.update(socket.assigns.limits, column_id, @page_size * 2, &(&1 + @page_size))

    {:noreply, assign(socket, :limits, limits)}
  end

  def handle_event("show_new_request", _params, socket) do
    {:noreply, assign(socket, :show_new_request, true)}
  end

  @impl true
  def handle_info(:hide_new_request, socket) do
    {:noreply, assign(socket, :show_new_request, false)}
  end

  def handle_info({:new_request_created, _request}, socket) do
    board = load_board(socket)

    filtered_board =
      apply_all_filters(
        board,
        socket.assigns.filter_perspective,
        socket.assigns.filter_priority,
        socket.assigns.filter_team,
        socket.assigns.filter_search
      )

    {:noreply,
     socket
     |> put_flash(:info, gettext("Request created successfully"))
     |> assign(:board, filtered_board)
     |> assign(:total_count, count_all_cards(filtered_board))}
  end

  def handle_info({:new_request_flash, kind, msg}, socket) do
    {:noreply, put_flash(socket, kind, msg)}
  end

  defp build_params(socket, updates) do
    updates_map = Enum.into(updates, %{}, fn {k, v} -> {Atom.to_string(k), v} end)

    %{
      "perspective" => Atom.to_string(socket.assigns.filter_perspective),
      "priority" => socket.assigns.filter_priority,
      "team" => socket.assigns.filter_team,
      "search" => socket.assigns.filter_search,
      "teams" => socket.assigns.teams_param
    }
    |> Map.merge(updates_map)
    |> Enum.reject(fn {_k, v} -> v in ["all", ""] end)
    |> Enum.into(%{})
  end

  # My board only shows the viewer's own teams: unknown ids are dropped and an
  # empty selection means all of them. `teams_param` stays empty for "all" so
  # the URL keeps following the user's teams.
  defp assign_selected_teams(%{assigns: %{live_action: :mine}} = socket, teams_param) do
    requested_ids =
      teams_param
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.flat_map(fn id ->
        case Integer.parse(id) do
          {int, ""} -> [int]
          _ -> []
        end
      end)

    team_ids = socket.assigns.team_ids

    selected_ids =
      case Enum.filter(team_ids, &(&1 in requested_ids)) do
        [] -> team_ids
        ids -> ids
      end

    socket
    |> assign(:selected_team_ids, selected_ids)
    |> assign(
      :teams_param,
      if(selected_ids == team_ids, do: "", else: Enum.join(selected_ids, ","))
    )
  end

  defp assign_selected_teams(socket, _teams_param), do: assign(socket, :teams_param, "")

  defp load_board(%{assigns: %{live_action: :mine}} = socket),
    do: Kanbans.get_my_board(socket.assigns.selected_team_ids)

  defp load_board(socket),
    do: Kanbans.get_board!(socket.assigns.raw_board_id, socket.assigns.team_ids)

  defp board_path(%{assigns: %{live_action: :mine}}, params), do: ~p"/boards/mine?#{params}"
  defp board_path(socket, params), do: ~p"/boards/#{socket.assigns.raw_board_id}?#{params}"

  defp can_access_board?(user, board) do
    Accounts.can_access_team?(user, board.team_id) or
      Accounts.can_access_team?(user, board.team_b_id)
  end

  defp apply_all_filters(
         board,
         filter_perspective,
         filter_priority,
         filter_team,
         filter_search
       ) do
    filtered_columns =
      Enum.map(board.columns, fn column ->
        filtered_cards =
          column.cards
          |> filter_by_perspective(filter_perspective, board.team_id)
          |> filter_by_priority(filter_priority)
          |> filter_by_team(filter_team)
          |> filter_by_search(filter_search)

        Map.put(column, :cards, filtered_cards)
      end)

    Map.put(board, :columns, filtered_columns)
  end

  # "Us" is the board's own-side team, i.e. the viewer's team within the pair.
  defp filter_by_perspective(cards, filter_perspective, our_team_id) do
    Enum.filter(cards, fn card ->
      case filter_perspective do
        :all ->
          true

        :created_by_us ->
          card.request.requesting_team_id == our_team_id

        :assigned_to_us ->
          card.request.assigned_to_team_id == our_team_id

        _ ->
          true
      end
    end)
  end

  defp filter_by_priority(cards, "all"), do: cards

  defp filter_by_priority(cards, priority) do
    priority_int = String.to_integer(priority)
    Enum.filter(cards, &(&1.request.priority == priority_int))
  end

  defp filter_by_team(cards, "all"), do: cards

  defp filter_by_team(cards, team_id) do
    team_int = String.to_integer(team_id)

    Enum.filter(cards, fn card ->
      card.request.requesting_team_id == team_int or card.request.assigned_to_team_id == team_int
    end)
  end

  defp filter_by_search(cards, ""), do: cards

  defp filter_by_search(cards, search) do
    Enum.filter(cards, &Requests.matches_search?(&1.request, search))
  end

  defp count_all_cards(board) do
    board.columns
    |> Enum.map(&length(&1.cards))
    |> Enum.sum()
  end
end
