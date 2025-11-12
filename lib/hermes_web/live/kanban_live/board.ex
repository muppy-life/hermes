defmodule HermesWeb.KanbanLive.Board do
  use HermesWeb, :live_view

  alias Hermes.Kanbans
  alias Hermes.Accounts
  alias Hermes.Requests
  alias HermesWeb.NavigationHistory

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    current_user = socket.assigns[:current_user]
    board = Kanbans.get_board!(board_id, current_user.team_id)

    if can_access_board?(current_user, board) do
      {:ok,
       socket
       |> NavigationHistory.assign_return_path(default: ~p"/boards")
       |> assign(:raw_board_id, board_id)
       |> assign(:page_title, board.name)
       |> assign(:teams, Accounts.list_teams())}
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

    current_user = socket.assigns[:current_user]
    board_id = socket.assigns[:raw_board_id]
    board = Kanbans.get_board!(board_id, current_user.team_id)

    filtered_board = apply_all_filters(board, filter_perspective, filter_priority, filter_team, current_user.team_id)
    total_count = count_all_cards(filtered_board)

    {:noreply,
     socket
     |> assign(:board, filtered_board)
     |> assign(:filter_perspective, filter_perspective)
     |> assign(:filter_priority, filter_priority)
     |> assign(:filter_team, filter_team)
     |> assign(:total_count, total_count)}
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
        %{"card_id" => card_id, "column_id" => _column_id, "position" => _position, "new_status" => new_status},
        socket
      ) do
    request_id = String.to_integer(card_id)
    current_user = socket.assigns[:current_user]

    # Get the request and update its status
    request = Requests.get_request!(request_id)

    case Requests.update_request(request, %{status: new_status}, current_user.id) do
      {:ok, _updated_request} ->
        # Reload the board with updated data
        board = Kanbans.get_board!(socket.assigns.raw_board_id, current_user.team_id)
        filtered_board = apply_all_filters(
          board,
          socket.assigns.filter_perspective,
          socket.assigns.filter_priority,
          socket.assigns.filter_team,
          current_user.team_id
        )
        total_count = count_all_cards(filtered_board)
        {:noreply, socket |> assign(:board, filtered_board) |> assign(:total_count, total_count)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move card")}
    end
  end

  def handle_event("set_filter", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/boards/#{socket.assigns.raw_board_id}?#{build_params(socket, perspective: filter)}"
     )}
  end

  def handle_event("apply_filters", %{"priority" => priority, "team" => team}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/boards/#{socket.assigns.raw_board_id}?#{build_params(socket, priority: priority, team: team)}"
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/boards/#{socket.assigns.raw_board_id}?perspective=#{socket.assigns.filter_perspective}"
     )}
  end

  defp build_params(socket, updates) do
    updates_map = Enum.into(updates, %{}, fn {k, v} -> {Atom.to_string(k), v} end)

    %{
      "perspective" => Atom.to_string(socket.assigns.filter_perspective),
      "priority" => socket.assigns.filter_priority,
      "team" => socket.assigns.filter_team
    }
    |> Map.merge(updates_map)
    |> Enum.filter(fn {_k, v} -> v != "all" end)
    |> Enum.into(%{})
  end

  defp can_access_board?(user, board) do
    Accounts.can_access_team?(user, board.team_id) or
      Accounts.can_access_team?(user, board.team_b_id)
  end

  defp apply_all_filters(board, filter_perspective, filter_priority, filter_team, current_user_team_id) do
    filtered_columns =
      Enum.map(board.columns, fn column ->
        filtered_cards =
          column.cards
          |> filter_by_perspective(filter_perspective, current_user_team_id)
          |> filter_by_priority(filter_priority)
          |> filter_by_team(filter_team)

        Map.put(column, :cards, filtered_cards)
      end)

    Map.put(board, :columns, filtered_columns)
  end

  defp filter_by_perspective(cards, filter_perspective, current_user_team_id) do
    Enum.filter(cards, fn card ->
      case filter_perspective do
        :all ->
          true

        :created_by_us ->
          card.request.requesting_team_id == current_user_team_id

        :assigned_to_us ->
          card.request.assigned_to_team_id == current_user_team_id

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

  defp count_all_cards(board) do
    board.columns
    |> Enum.map(& length(&1.cards))
    |> Enum.sum()
  end
end
