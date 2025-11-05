defmodule Hermes.Kanbans.Card do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kanban_cards" do
    field :title, :string
    field :description, :string
    field :position, :integer

    belongs_to :column, Hermes.Kanbans.Column
    belongs_to :request, Hermes.Requests.Request

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:title, :description, :position, :column_id, :request_id])
    |> validate_required([:position, :column_id, :request_id])
  end
end
