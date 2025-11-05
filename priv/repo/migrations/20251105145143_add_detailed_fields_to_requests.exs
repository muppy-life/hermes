defmodule Hermes.Repo.Migrations.AddDetailedFieldsToRequests do
  use Ecto.Migration

  def change do
    # Create enum types
    execute "CREATE TYPE request_kind AS ENUM ('problem', 'new_need', 'improvement')",
            "DROP TYPE request_kind"

    execute "CREATE TYPE target_user_type AS ENUM ('internal', 'external')",
            "DROP TYPE target_user_type"

    execute "CREATE TYPE goal_target_type AS ENUM ('interface_view', 'report_file', 'alert_message')",
            "DROP TYPE goal_target_type"

    alter table(:requests) do
      # Step 1: Kind of request - problem, new_need, improvement
      add :kind, :request_kind

      # Step 2: Priority (already exists as integer 1-5)
      # We'll map: 1=Low, 2=Normal, 3=Important, 4=Critical

      # Step 3: Target user - internal, external
      add :target_user_type, :target_user_type

      # Step 4: Current situation description
      add :current_situation, :text

      # Step 5: Goal description
      add :goal_description, :text

      # Step 6: Data type description (if applies)
      add :data_description, :text

      # Step 7: Goal target - interface_view, report_file, alert_message
      add :goal_target, :goal_target_type

      # Step 7 continued: Final output/expected result details
      add :expected_output, :text
    end
  end
end
