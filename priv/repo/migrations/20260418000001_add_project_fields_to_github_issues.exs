defmodule Hermes.Repo.Migrations.AddProjectFieldsToGithubIssues do
  use Ecto.Migration

  def change do
    alter table(:github_issues) do
      add :project_item_id, :string
      add :project_status, :string
      add :last_sync_source, :string
      add :last_sync_at, :utc_datetime
    end

    create index(:github_issues, [:project_item_id])
  end
end
