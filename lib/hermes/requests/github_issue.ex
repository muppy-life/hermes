defmodule Hermes.Requests.GitHubIssue do
  @moduledoc """
  A GitHub issue linked to a Hermes request (1:1).

  Stores the canonical `(owner, repo, number)` identity plus the HTML URL
  and a cached state for the linked issue.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "github_issues" do
    field :owner, :string
    field :repo, :string
    field :number, :integer
    field :url, :string
    field :state, :string
    field :last_synced_at, :utc_datetime

    belongs_to :request, Hermes.Requests.Request

    timestamps(type: :utc_datetime)
  end

  @required [:request_id, :owner, :repo, :number, :url]
  @optional [:state, :last_synced_at]

  def changeset(github_issue, attrs) do
    github_issue
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:state, ["open", "closed"], message: "must be open or closed")
    |> unique_constraint(:request_id)
    |> unique_constraint([:owner, :repo, :number],
      name: :github_issues_owner_repo_number_index
    )
    |> foreign_key_constraint(:request_id)
  end
end
