defmodule Hermes.TechOps.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:open, :in_progress, :blocked, :resolved, :closed]

  schema "tech_ops_tasks" do
    field :recorded_on, :date
    field :reported_problem, :string
    field :reporter, :string
    field :issue_origin, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolution, :string
    field :cause, :string

    belongs_to :responsible, Hermes.Accounts.User
    belongs_to :team, Hermes.Accounts.Team

    timestamps(type: :utc_datetime)
  end

  @doc "Available status values, in lifecycle order."
  def statuses, do: @statuses

  @doc "Human-readable label for a status (plain string; translate at the view layer)."
  def status_label(:open), do: "Open"
  def status_label(:in_progress), do: "In progress"
  def status_label(:blocked), do: "Blocked"
  def status_label(:resolved), do: "Resolved"
  def status_label(:closed), do: "Closed"
  def status_label(_), do: "Unknown"

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :recorded_on,
      :reported_problem,
      :reporter,
      :issue_origin,
      :status,
      :resolution,
      :cause,
      :responsible_id,
      :team_id
    ])
    |> validate_required([:recorded_on, :reported_problem, :status])
    |> foreign_key_constraint(:responsible_id)
    |> foreign_key_constraint(:team_id)
  end
end
