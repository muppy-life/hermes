defmodule Hermes.Repo.Migrations.CreateKanbanBoards do
  use Ecto.Migration

  def change do
    create table(:kanban_boards) do
      add :name, :string
      add :team_id, references(:teams, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:kanban_boards, [:team_id])
  end
end
