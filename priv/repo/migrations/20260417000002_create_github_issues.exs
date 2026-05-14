defmodule Hermes.Repo.Migrations.CreateGithubIssues do
  use Ecto.Migration

  def change do
    create table(:github_issues) do
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      add :owner, :string, null: false
      add :repo, :string, null: false
      add :number, :integer, null: false
      add :url, :string, null: false
      add :state, :string
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:github_issues, [:request_id])
    create unique_index(:github_issues, [:owner, :repo, :number])
  end
end
