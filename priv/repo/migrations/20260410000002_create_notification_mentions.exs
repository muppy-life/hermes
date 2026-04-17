defmodule Hermes.Repo.Migrations.CreateNotificationMentions do
  use Ecto.Migration

  def change do
    create table(:notification_mentions) do
      add :notification_id, references(:notifications, on_delete: :delete_all), null: false
      add :comment_id, references(:request_comments, on_delete: :delete_all), null: false
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      add :mentioned_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:notification_mentions, [:notification_id])
    create index(:notification_mentions, [:comment_id])
    create index(:notification_mentions, [:request_id])
  end
end
