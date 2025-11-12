defmodule HermesWeb.KanbanLive.Board do
  use HermesWeb, :live_view

  alias Hermes.Kanbans
  alias Hermes.Accounts
  alias Hermes.Requests

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    current_user = socket.assigns[:current_user]
    board = Kanbans.get_board!(board_id, current_user.team_id)

    if can_access_board?(current_user, board) do
      filtered_board = filter_board_by_perspective(board, :all, current_user.team_id)

      {:ok,
       socket
       |> assign(:board, filtered_board)
       |> assign(:raw_board_id, board_id)
       |> assign(:page_title, board.name)
       |> assign(:filter_perspective, :all)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access this board")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

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
        filtered_board = filter_board_by_perspective(board, socket.assigns.filter_perspective, current_user.team_id)
        {:noreply, assign(socket, :board, filtered_board)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move card")}
    end
  end

  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter_atom = String.to_existing_atom(filter)
    current_user = socket.assigns[:current_user]
    board_id = socket.assigns[:raw_board_id]

    board = Kanbans.get_board!(board_id, current_user.team_id)
    filtered_board = filter_board_by_perspective(board, filter_atom, current_user.team_id)

    {:noreply, socket
      |> assign(:board, filtered_board)
      |> assign(:filter_perspective, filter_atom)}
  end

  defp can_access_board?(user, board) do
    Accounts.can_access_team?(user, board.team_id) or
      Accounts.can_access_team?(user, board.team_b_id)
  end

  defp filter_board_by_perspective(board, filter_perspective, current_user_team_id) do
    filtered_columns =
      Enum.map(board.columns, fn column ->
        filtered_cards =
          Enum.filter(column.cards, fn card ->
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

        Map.put(column, :cards, filtered_cards)
      end)

    Map.put(board, :columns, filtered_columns)
  end
end
