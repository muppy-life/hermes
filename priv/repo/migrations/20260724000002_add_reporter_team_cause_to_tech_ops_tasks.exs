defmodule Hermes.Repo.Migrations.AddReporterTeamCauseToTechOpsTasks do
  use Ecto.Migration

  def change do
    alter table(:tech_ops_tasks) do
      add :reporter, :string
      add :cause, :text
      add :team_id, references(:teams, on_delete: :nilify_all)
    end

    create index(:tech_ops_tasks, [:team_id])
  end
end
