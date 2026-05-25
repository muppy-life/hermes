defmodule Hermes.Repo.Migrations.AddPreDiscardStatusToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :pre_discard_status, :string
    end
  end
end
