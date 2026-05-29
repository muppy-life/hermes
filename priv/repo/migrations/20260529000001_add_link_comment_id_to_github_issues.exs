defmodule Hermes.Repo.Migrations.AddLinkCommentIdToGithubIssues do
  use Ecto.Migration

  def change do
    alter table(:github_issues) do
      add :link_comment_id, :bigint
    end
  end
end
