defmodule Hermes.Requests.Request do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requests" do
    field :title, :string
    field :description, :string
    field :priority, :integer
    field :status, :string
    field :deadline, :date

    # Multi-step form fields
    field :kind, Ecto.Enum, values: [:problem, :new_need, :improvement]
    field :target_user_type, Ecto.Enum, values: [:internal, :external]
    field :current_situation, :string
    field :goal_description, :string
    field :data_description, :string
    field :goal_target, Ecto.Enum, values: [:interface_view, :report_file, :alert_message]
    field :expected_output, :string
    field :solution_diagram, :string

    belongs_to :requesting_team, Hermes.Accounts.Team
    belongs_to :assigned_to_team, Hermes.Accounts.Team
    belongs_to :created_by, Hermes.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :title,
      :description,
      :priority,
      :status,
      :deadline,
      :kind,
      :target_user_type,
      :current_situation,
      :goal_description,
      :data_description,
      :goal_target,
      :expected_output,
      :solution_diagram,
      :requesting_team_id,
      :assigned_to_team_id,
      :created_by_id
    ])
    |> validate_required([
      :kind,
      :priority,
      :target_user_type,
      :current_situation,
      :goal_description,
      :goal_target,
      :expected_output,
      :requesting_team_id,
      :created_by_id
    ])
    |> validate_inclusion(:priority, 1..4)
    |> validate_inclusion(:status, [
      "new",
      "pending",
      "in_progress",
      "review",
      "completed",
      "blocked"
    ])
  end

  def priority_label(priority) do
    case priority do
      1 -> "Low"
      2 -> "Normal"
      3 -> "Important"
      4 -> "Critical"
      _ -> "Unknown"
    end
  end

  def kind_label(kind) do
    case kind do
      :problem -> "Problem with current app or service"
      :new_need -> "New need"
      :improvement -> "Improvement suggestion"
      _ -> "Unknown"
    end
  end

  def target_user_label(type) do
    case type do
      :internal -> "Internal user (company team)"
      :external -> "External user (client, provider)"
      _ -> "Unknown"
    end
  end

  def goal_target_label(target) do
    case target do
      :interface_view -> "Interface / View"
      :report_file -> "Report File"
      :alert_message -> "Alert / Message / Communication"
      _ -> "Unknown"
    end
  end
end
