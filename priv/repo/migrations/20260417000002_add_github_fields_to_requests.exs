defmodule Hermes.Repo.Migrations.AddGithubFieldsToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :github_issue_number, :integer
      add :github_issue_url, :string
      add :github_repo, :string
    end

    create index(:requests, [:github_issue_number])
  end
end
