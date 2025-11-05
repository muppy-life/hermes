defmodule Hermes.Kanbans.Board do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kanban_boards" do
    field :name, :string

    belongs_to :team, Hermes.Accounts.Team
    has_many :columns, Hermes.Kanbans.Column, foreign_key: :board_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name, :team_id])
    |> validate_required([:name, :team_id])
  end
end
