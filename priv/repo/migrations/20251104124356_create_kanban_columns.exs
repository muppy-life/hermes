defmodule Hermes.Repo.Migrations.CreateKanbanColumns do
  use Ecto.Migration

  def change do
    create table(:kanban_columns) do
      add :name, :string
      add :position, :integer
      add :board_id, references(:kanban_boards, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:kanban_columns, [:board_id])
  end
end
