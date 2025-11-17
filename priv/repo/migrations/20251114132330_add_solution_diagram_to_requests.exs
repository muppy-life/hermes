defmodule Hermes.Repo.Migrations.AddSolutionDiagramToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :solution_diagram, :text
    end
  end
end
