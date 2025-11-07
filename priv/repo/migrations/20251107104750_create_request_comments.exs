defmodule Hermes.Repo.Migrations.CreateRequestComments do
  use Ecto.Migration

  def change do
    create table(:request_comments) do
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false
      add :content, :text, null: false

      timestamps()
    end

    create index(:request_comments, [:request_id])
    create index(:request_comments, [:user_id])
    create index(:request_comments, [:inserted_at])
  end
end
