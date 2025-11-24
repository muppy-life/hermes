defmodule Hermes.Repo.Migrations.AddTeamPairToBoards do
  use Ecto.Migration

  def change do
    alter table(:kanban_boards) do
      add :team_b_id, references(:teams, on_delete: :delete_all)
    end

    create index(:kanban_boards, [:team_b_id])

    # Create a unique index to ensure we don't have duplicate team pairs
    # This ensures boards are unique for each team pair combination
    create unique_index(:kanban_boards, [:team_id, :team_b_id],
             name: :kanban_boards_team_pair_index,
             where: "team_id < team_b_id"
           )

    create unique_index(:kanban_boards, [:team_b_id, :team_id],
             name: :kanban_boards_team_pair_reverse_index,
             where: "team_b_id < team_id"
           )
  end
end
