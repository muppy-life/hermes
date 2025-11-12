defmodule Hermes.Accounts do
  @moduledoc """
  The Accounts context for managing users and teams.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo
  alias Hermes.Accounts.{User, Team}

  ## Team functions

  def list_teams do
    Repo.all(Team)
  end

  def get_team!(id), do: Repo.get!(Team, id)

  def create_team(attrs \\ %{}) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  def delete_team(%Team{} = team) do
    Repo.delete(team)
  end

  ## User functions

  def list_users do
    Repo.all(User) |> Repo.preload(:team)
  end

  def get_user!(id) do
    Repo.get!(User, id) |> Repo.preload(:team)
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email) |> Repo.preload(:team)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  ## Authorization helpers

  def is_dev_team?(%User{role: "dev_team"}), do: true
  def is_dev_team?(%User{role: "admin"}), do: true
  def is_dev_team?(_), do: false

  def is_product_owner?(%User{role: "product_owner"}), do: true
  def is_product_owner?(%User{role: "admin"}), do: true
  def is_product_owner?(_), do: false

  def can_access_team?(%User{team_id: team_id}, team_id), do: true
  def can_access_team?(_, _), do: false
end
