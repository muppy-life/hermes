defmodule Hermes.TechOps.Reporter do
  @moduledoc """
  Canonical list of who reports tech ops issues. Values may name people without
  a Hermes account, so this is a free-form managed list rather than a user FK.
  Deduplicated on a normalized key so casing/whitespace variants collapse.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tech_ops_reporters" do
    field :name, :string
    field :normalized, :string

    has_many :tasks, Hermes.TechOps.Task, foreign_key: :reporter_id

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
  def changeset(reporter, attrs) do
    reporter
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
