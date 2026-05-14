defmodule Hermes.Repo.Migrations.UniqueProjectItemId do
  use Ecto.Migration

  def change do
    drop_if_exists index(:github_issues, [:project_item_id])

    create unique_index(:github_issues, [:project_item_id], where: "project_item_id IS NOT NULL")
  end
end
