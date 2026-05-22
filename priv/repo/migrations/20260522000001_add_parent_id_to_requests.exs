defmodule Hermes.Repo.Migrations.AddParentIdToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :parent_id, references(:requests, on_delete: :nilify_all), null: true
    end

    create index(:requests, [:parent_id])
  end
end
