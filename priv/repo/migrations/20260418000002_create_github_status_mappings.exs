defmodule Hermes.Repo.Migrations.CreateGithubStatusMappings do
  use Ecto.Migration

  def change do
    create table(:github_status_mappings) do
      add :github_option_id, :string, null: false
      add :github_option_name, :string, null: false
      add :hermes_status, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:github_status_mappings, [:github_option_id])
    create unique_index(:github_status_mappings, [:hermes_status])
  end
end
