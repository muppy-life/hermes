defmodule Hermes.Repo.Migrations.AddImpactFieldsToRequests do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE impact_area AS ENUM ('cost_reduction', 'revenue_increase', 'efficiency', 'product_ux', 'other')",
            "DROP TYPE impact_area"

    execute "CREATE TYPE impact_level AS ENUM ('high', 'medium', 'low')",
            "DROP TYPE impact_level"

    alter table(:requests) do
      # Step 3: Impact area - which area the request benefits
      add :impact_area, :impact_area

      # Step 3: Impact magnitude - how big the impact is
      add :impact_level, :impact_level
    end
  end
end
