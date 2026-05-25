defmodule Hermes.Repo.Migrations.AddDiscardFieldsToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :discard_reason_category, :string
      add :discard_reason, :text
      add :discarded_by_id, references(:users, on_delete: :nilify_all)
      add :discarded_at, :utc_datetime
    end

    create index(:requests, [:discarded_by_id])
    create index(:requests, [:status])
  end
end
