defmodule Hermes.Repo.Migrations.CreateUserTeams do
  use Ecto.Migration

  # Extra teams a user is involved in, on top of their primary `users.team_id`.
  def change do
    create table(:user_teams, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false
    end

    create unique_index(:user_teams, [:user_id, :team_id])
    create index(:user_teams, [:team_id])
  end
end
