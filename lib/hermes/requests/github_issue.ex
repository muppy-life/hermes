defmodule Hermes.Requests.GitHubIssue do
  @moduledoc """
  A GitHub issue linked to a Hermes request (1:1).

  Stores the canonical `(owner, repo, number)` identity, the HTML URL,
  and project board metadata (item ID + current status column).
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

    field :project_item_id, :string
    field :project_status, :string
    field :last_sync_source, :string
    field :last_sync_at, :utc_datetime

    belongs_to :request, Hermes.Requests.Request

    timestamps(type: :utc_datetime)
  end

  @required [:request_id, :owner, :repo, :number, :url]
  @optional [
    :state,
    :last_synced_at,
    :project_item_id,
    :project_status,
    :last_sync_source,
    :last_sync_at
  ]

  def changeset(github_issue, attrs) do
    github_issue
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:last_sync_source, ["hermes", "webhook"],
      message: "must be hermes or webhook"
    )
    |> unique_constraint(:request_id)
    |> unique_constraint([:owner, :repo, :number],
      name: :github_issues_owner_repo_number_index
    )
    |> foreign_key_constraint(:request_id)
  end
end
