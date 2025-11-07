defmodule Hermes.Repo.Migrations.CreateRequestChanges do
  use Ecto.Migration

  def change do
    create table(:request_changes) do
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :field, :string
      add :old_value, :text
      add :new_value, :text
      add :changes, :map

      timestamps(updated_at: false)
    end

    create index(:request_changes, [:request_id])
    create index(:request_changes, [:user_id])
    create index(:request_changes, [:inserted_at])
  end
end
