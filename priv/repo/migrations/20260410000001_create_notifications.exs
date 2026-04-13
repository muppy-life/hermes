defmodule Hermes.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :read_at, :utc_datetime

      timestamps()
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :read_at])
    create index(:notifications, [:type])
  end
end
