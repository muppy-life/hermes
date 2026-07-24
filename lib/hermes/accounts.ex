defmodule Hermes.Accounts do
  @moduledoc """
  The Accounts context for managing users and teams.
  """

  import Ecto.Query, warn: false
  alias Hermes.Accounts.{ApiToken, Team, User}
  alias Hermes.Repo

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

  @doc """
  Returns a map of `%{team_id => member_count}` computed with a single
  aggregate query (no rows loaded).
  """
  def count_users_by_team do
    from(u in User,
      where: is_nil(u.deleted_at),
      group_by: u.team_id,
      select: {u.team_id, count(u.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the current number of members in the given team.
  """
  def count_team_members(team_id) do
    from(u in User, where: u.team_id == ^team_id and is_nil(u.deleted_at), select: count(u.id))
    |> Repo.one()
  end

  ## User functions

  def list_users do
    from(u in User, where: is_nil(u.deleted_at))
    |> Repo.all()
    |> Repo.preload(:team)
  end

  @doc """
  Fetches a user by id regardless of soft-delete state.

  Used for resolving historical references (e.g. the author of a request that
  was created by a since-deleted user). Do NOT use this for authentication or
  active-user listings — use `get_active_user/1` / `get_user_by_email/1` there.
  """
  def get_user!(id) do
    Repo.get!(User, id) |> Repo.preload(:team)
  end

  @doc """
  Fetches an active (non-deleted) user by id, or nil. Used by the auth layer so
  a soft-deleted user cannot keep an existing session alive.
  """
  def get_active_user(id) do
    from(u in User, where: u.id == ^id and is_nil(u.deleted_at))
    |> Repo.one()
    |> Repo.preload(:team)
  end

  def get_user_by_email(email) when is_binary(email) do
    from(u in User, where: u.email == ^email and is_nil(u.deleted_at))
    |> Repo.one()
    |> Repo.preload(:team)
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

  @doc """
  Soft-deletes a user by stamping `deleted_at`. The row is preserved so that
  historical references (requests, comments) keep resolving their author, but
  the user becomes invisible to active listings, lookups, and login.
  """
  def delete_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def update_last_seen(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def list_users_by_team(team_id) do
    from(u in User, where: u.team_id == ^team_id and is_nil(u.deleted_at))
    |> Repo.all()
  end

  def get_dev_team do
    from(t in Team,
      join: u in User,
      on: u.team_id == t.id,
      where: u.role == "dev_team",
      order_by: [asc: t.id],
      limit: 1
    )
    |> Repo.one()
  end

  def list_recently_active_users(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    from(u in User,
      where: not is_nil(u.last_seen_at) and u.last_seen_at >= ^cutoff and is_nil(u.deleted_at),
      order_by: [desc: u.last_seen_at],
      preload: :team
    )
    |> Repo.all()
  end

  ## Authorization helpers

  @doc """
  Checks if a user is a system administrator.
  System admins have access to all admin panels.
  """
  def is_admin?(%User{is_admin: true}), do: true
  def is_admin?(_), do: false

  def is_dev_team?(%User{role: "dev_team"}), do: true
  def is_dev_team?(%User{role: "admin"}), do: true
  def is_dev_team?(%User{is_admin: true}), do: true
  def is_dev_team?(_), do: false

  def is_product_owner?(%User{role: "product_owner"}), do: true
  def is_product_owner?(%User{role: "admin"}), do: true
  def is_product_owner?(%User{is_admin: true}), do: true
  def is_product_owner?(_), do: false

  def can_access_team?(%User{is_admin: true}, _), do: true
  def can_access_team?(%User{team_id: team_id}, team_id), do: true
  def can_access_team?(_, _), do: false

  ## API token functions

  @doc """
  Creates an API token for `user`. Returns `{:ok, raw_token, api_token}` where
  `raw_token` is the plaintext token to display once (never stored) and
  `api_token` is the persisted record holding only its hash.
  """
  def create_api_token(%User{} = user, name) do
    {raw, changeset} = ApiToken.build(user, %{name: name})

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, raw, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Resolves an active user from a raw API token, or returns `nil`.

  Touches `last_used_at` on a successful match. A soft-deleted user's tokens
  stop working, mirroring session auth.
  """
  def get_user_by_api_token(raw) when is_binary(raw) do
    hash = ApiToken.hash_token(raw)

    query =
      from t in ApiToken,
        join: u in User,
        on: u.id == t.user_id,
        where: t.token_hash == ^hash and is_nil(u.deleted_at),
        select: t

    case Repo.one(query) do
      nil ->
        nil

      token ->
        touch_api_token(token)
        get_active_user(token.user_id)
    end
  end

  def get_user_by_api_token(_), do: nil

  defp touch_api_token(%ApiToken{} = token) do
    token
    |> Ecto.Changeset.change(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  @doc "Lists a user's API tokens (most recent first). Raw tokens are never returned."
  def list_api_tokens(%User{} = user) do
    from(t in ApiToken, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc "Lists all API tokens across users with their owner preloaded (admin view)."
  def list_all_api_tokens do
    from(t in ApiToken, order_by: [desc: t.inserted_at], preload: [:user])
    |> Repo.all()
  end

  def get_api_token!(id), do: Repo.get!(ApiToken, id)

  @doc "Revokes (deletes) an API token."
  def revoke_api_token(%ApiToken{} = token), do: Repo.delete(token)
end
