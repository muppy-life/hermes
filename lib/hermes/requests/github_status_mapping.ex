defmodule Hermes.Requests.GitHubStatusMapping do
  @moduledoc """
  Maps a GitHub Projects v2 Status field option to a Hermes request status.

  Mapping is 1:1 in both directions so reverse-sync (webhook) and
  forward-sync (Hermes -> GitHub) can resolve without ambiguity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @hermes_statuses ~w(new need_requirement pending future_planning todo_in_sprint in_progress review completed blocked)

  schema "github_status_mappings" do
    field :github_option_id, :string
    field :github_option_name, :string
    field :hermes_status, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:github_option_id, :github_option_name, :hermes_status])
    |> validate_required([:github_option_id, :github_option_name, :hermes_status])
    |> validate_inclusion(:hermes_status, @hermes_statuses)
    |> unique_constraint(:github_option_id)
    |> unique_constraint(:hermes_status)
  end

  def hermes_statuses, do: @hermes_statuses
end
