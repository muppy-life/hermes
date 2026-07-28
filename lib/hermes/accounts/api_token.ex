defmodule Hermes.Accounts.ApiToken do
  @moduledoc """
  Personal API token for programmatic access (REST API + MCP).

  Only the SHA256 hash of the token is stored; the raw token is shown once at
  creation time and never persisted. Hashing scheme matches the app's password
  handling (SHA256 hex).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @rand_size 32

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Hermes.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a `{raw_token, changeset}` pair for a new token belonging to `user`.

  The raw token is returned to the caller so it can be shown once; only its
  hash is stored.
  """
  def build(user, attrs) do
    raw = generate_raw_token()

    changeset =
      %__MODULE__{}
      |> cast(attrs, [:name])
      |> validate_required([:name])
      |> put_change(:token_hash, hash_token(raw))
      |> put_change(:user_id, user.id)
      |> unique_constraint(:token_hash)

    {raw, changeset}
  end

  @doc "Generates a random, URL-safe raw token string (prefixed for identification)."
  def generate_raw_token do
    "hermes_" <> (:crypto.strong_rand_bytes(@rand_size) |> Base.url_encode64(padding: false))
  end

  @doc "Hashes a raw token with SHA256 (hex), matching the password scheme."
  def hash_token(raw) when is_binary(raw) do
    :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
  end
end
