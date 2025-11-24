defmodule Hermes.Repo.Migrations.AddDeadlineToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :deadline, :date, null: true
    end
  end
end
