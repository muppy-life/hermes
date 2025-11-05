defmodule Hermes.Repo.Migrations.CreateKanbanCards do
  use Ecto.Migration

  def change do
    create table(:kanban_cards) do
      add :title, :string
      add :description, :text
      add :position, :integer
      add :column_id, references(:kanban_columns, on_delete: :nothing)
      add :request_id, references(:requests, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:kanban_cards, [:column_id])
    create index(:kanban_cards, [:request_id])
  end
end
