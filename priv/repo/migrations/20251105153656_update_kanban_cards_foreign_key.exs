defmodule Hermes.Repo.Migrations.UpdateKanbanCardsForeignKey do
  use Ecto.Migration

  def change do
    # Drop the existing foreign key constraint
    drop constraint(:kanban_cards, "kanban_cards_request_id_fkey")

    # Add a new foreign key with on_delete: :delete_all
    alter table(:kanban_cards) do
      modify :request_id, references(:requests, on_delete: :delete_all)
    end
  end
end
