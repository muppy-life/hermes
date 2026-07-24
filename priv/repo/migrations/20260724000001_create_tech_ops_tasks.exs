defmodule Hermes.Repo.Migrations.CreateTechOpsTasks do
  use Ecto.Migration

  def change do
    create table(:tech_ops_tasks) do
      add :recorded_on, :date, null: false
      add :reported_problem, :text, null: false
      add :issue_origin, :string
      add :status, :string, null: false, default: "open"
      add :resolution, :text
      add :responsible_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tech_ops_tasks, [:responsible_id])
    create index(:tech_ops_tasks, [:status])
  end
end
