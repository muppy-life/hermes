defmodule Hermes.Kanbans.Column do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kanban_columns" do
    field :name, :string
    field :position, :integer

    belongs_to :board, Hermes.Kanbans.Board
    has_many :cards, Hermes.Kanbans.Card, foreign_key: :column_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :position, :board_id])
    |> validate_required([:name, :position, :board_id])
  end
end
