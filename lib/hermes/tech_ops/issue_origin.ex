defmodule Hermes.TechOps.IssueOrigin do
  @moduledoc """
  Canonical list of where a tech ops issue came from (a user, a place in the
  code or app, etc.). Managed list, deduplicated on a normalized key so
  casing/whitespace variants collapse to one row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tech_ops_issue_origins" do
    field :name, :string
    field :normalized, :string

    has_many :tasks, Hermes.TechOps.Task, foreign_key: :issue_origin_id

    timestamps(type: :utc_datetime)
  end

  @doc "Normalized matching key: trimmed, lowercased, collapsed whitespace."
  def normalize(nil), do: ""

  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.downcase()
  end

  @doc false
  def changeset(origin, attrs) do
    origin
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> put_normalized()
    |> unique_constraint(:normalized)
  end

  defp put_normalized(changeset) do
    case get_field(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :normalized, normalize(name))
    end
  end
end
