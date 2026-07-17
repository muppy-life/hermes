defmodule Hermes.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :surname, :string
    field :email, :string
    field :hashed_password, :string
    field :role, :string
    field :is_admin, :boolean, default: false
    field :last_seen_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :team, Hermes.Accounts.Team
    has_many :created_requests, Hermes.Requests.Request, foreign_key: :created_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Human-readable identity for the UI: "Name Surname" when set, otherwise the
  email local part (e.g. "j.doe@acme.com" -> "j.doe").
  """
  def display_name(%__MODULE__{} = user) do
    [user.name, user.surname]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> user.email |> String.split("@") |> List.first()
      parts -> Enum.join(parts, " ")
    end
  end

  def display_name(_), do: nil

  @doc "Two-letter initials from the display name."
  def initials(%__MODULE__{} = user) do
    user
    |> display_name()
    |> String.split(~r/[\s._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  def initials(_), do: "?"

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :surname, :email, :hashed_password, :role, :team_id, :is_admin])
    |> validate_required([:email, :hashed_password, :role, :team_id])
    |> validate_inclusion(:role, ["admin", "dev_team", "team_member", "product_owner"])
    |> unique_constraint(:email, name: :users_email_active_index)
  end
end
