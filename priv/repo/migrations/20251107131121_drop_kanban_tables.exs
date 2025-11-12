defmodule Hermes.Repo.Migrations.DropKanbanTables do
  use Ecto.Migration

  def change do
    # Drop tables in reverse dependency order
    drop table(:kanban_cards)
    drop table(:kanban_columns)
    drop table(:kanban_boards)
  end
end
