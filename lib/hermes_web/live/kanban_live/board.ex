defmodule HermesWeb.KanbanLive.Board do
  use HermesWeb, :live_view

  alias Hermes.Kanbans
  alias Hermes.Accounts

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    board = Kanbans.get_board!(board_id)
    current_user = socket.assigns[:current_user]

    if can_access_board?(current_user, board) do
      {:ok,
       socket
       |> assign(:board, board)
       |> assign(:page_title, board.name)}
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
        %{"card_id" => card_id, "column_id" => column_id, "position" => position},
        socket
      ) do
    card_id = String.to_integer(card_id)
    column_id = String.to_integer(column_id)
    position = String.to_integer(position)

    case Kanbans.move_card(card_id, column_id, position) do
      {:ok, _card} ->
        board = Kanbans.get_board!(socket.assigns.board.id)
        {:noreply, assign(socket, :board, board)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move card")}
    end
  end

  defp can_access_board?(user, board) do
    Accounts.can_access_team?(user, board.team_id)
  end

  defp truncate_words(text, word_count) do
    words = String.split(text, ~r/\s+/)

    if length(words) <= word_count do
      text
    else
      words
      |> Enum.take(word_count)
      |> Enum.join(" ")
      |> Kernel.<>("...")
    end
  end
end
