defmodule Hermes.Kanbans do
  @moduledoc """
  The Kanbans context for managing kanban boards, columns, and cards.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo
  alias Hermes.Kanbans.{Board, Column, Card}

  ## Board functions

  def list_boards do
    Repo.all(Board) |> Repo.preload(:team)
  end

  def list_boards_by_team(team_id) do
    from(b in Board, where: b.team_id == ^team_id)
    |> Repo.all()
    |> Repo.preload(:team)
  end

  def get_board!(id) do
    Repo.get!(Board, id)
    |> Repo.preload([:team, columns: [cards: [request: [:requesting_team, :assigned_to_team]]]])
  end

  def create_board(attrs \\ %{}) do
    %Board{}
    |> Board.changeset(attrs)
    |> Repo.insert()
  end

  def update_board(%Board{} = board, attrs) do
    board
    |> Board.changeset(attrs)
    |> Repo.update()
  end

  def delete_board(%Board{} = board) do
    Repo.delete(board)
  end

  ## Column functions

  def list_columns_by_board(board_id) do
    from(c in Column, where: c.board_id == ^board_id, order_by: c.position)
    |> Repo.all()
  end

  def get_column!(id) do
    Repo.get!(Column, id)
    |> Repo.preload([:board, cards: :request])
  end

  def create_column(attrs \\ %{}) do
    %Column{}
    |> Column.changeset(attrs)
    |> Repo.insert()
  end

  def update_column(%Column{} = column, attrs) do
    column
    |> Column.changeset(attrs)
    |> Repo.update()
  end

  def delete_column(%Column{} = column) do
    Repo.delete(column)
  end

  ## Card functions

  def list_cards_by_column(column_id) do
    from(c in Card, where: c.column_id == ^column_id, order_by: c.position)
    |> Repo.all()
    |> Repo.preload(:request)
  end

  def get_card!(id) do
    Repo.get!(Card, id)
    |> Repo.preload([:column, :request])
  end

  def create_card(attrs \\ %{}) do
    %Card{}
    |> Card.changeset(attrs)
    |> Repo.insert()
  end

  def update_card(%Card{} = card, attrs) do
    card
    |> Card.changeset(attrs)
    |> Repo.update()
  end

  def delete_card(%Card{} = card) do
    Repo.delete(card)
  end

  def move_card(card_id, new_column_id, new_position) do
    card = get_card!(card_id)

    update_card(card, %{
      column_id: new_column_id,
      position: new_position
    })
  end

  ## Helper functions

  def initialize_board_columns(board_id) do
    default_columns = [
      %{name: "Backlog", position: 0, board_id: board_id},
      %{name: "To Do", position: 1, board_id: board_id},
      %{name: "In Progress", position: 2, board_id: board_id},
      %{name: "Review", position: 3, board_id: board_id},
      %{name: "Done", position: 4, board_id: board_id}
    ]

    Enum.each(default_columns, &create_column/1)
  end
end
