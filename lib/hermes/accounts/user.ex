defmodule Hermes.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :role, :string

    belongs_to :team, Hermes.Accounts.Team
    has_many :created_requests, Hermes.Requests.Request, foreign_key: :created_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :hashed_password, :role, :team_id])
    |> validate_required([:email, :hashed_password, :role, :team_id])
    |> validate_inclusion(:role, ["admin", "dev_team", "team_member", "product_owner"])
    |> unique_constraint(:email)
  end
end
