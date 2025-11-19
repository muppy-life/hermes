defmodule Hermes.Accounts.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string
    field :description, :string

    has_many :users, Hermes.Accounts.User
    has_many :requested_requests, Hermes.Requests.Request, foreign_key: :requesting_team_id
    has_many :assigned_requests, Hermes.Requests.Request, foreign_key: :assigned_to_team_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :description])
    |> validate_required([:name, :description])
  end
end
