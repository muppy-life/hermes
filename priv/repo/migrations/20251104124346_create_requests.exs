defmodule Hermes.Repo.Migrations.CreateRequests do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add :title, :string
      add :description, :text
      add :priority, :integer
      add :status, :string
      add :requesting_team_id, references(:teams, on_delete: :nothing)
      add :assigned_to_team_id, references(:teams, on_delete: :nothing)
      add :created_by_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:requests, [:requesting_team_id])
    create index(:requests, [:assigned_to_team_id])
    create index(:requests, [:created_by_id])
  end
end
