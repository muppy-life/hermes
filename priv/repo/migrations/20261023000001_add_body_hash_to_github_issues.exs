defmodule Hermes.Repo.Migrations.AddBodyHashToGithubIssues do
  use Ecto.Migration

  # Hash of the last issue body Hermes wrote, so a sync can tell whether
  # someone edited the body on GitHub since and leave it alone.
  def change do
    alter table(:github_issues) do
      add :body_hash, :string
    end
  end
end
