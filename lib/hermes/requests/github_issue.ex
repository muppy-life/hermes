defmodule Hermes.Requests.GitHubIssue do
  @moduledoc """
  A GitHub issue linked to a Hermes request (1:1).

  Stores the canonical `(owner, repo, number)` identity, the HTML URL,
  project board metadata (item ID + current status column), and the id of
  the "Linked to Hermes" comment so it can be removed on unlink.
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

    # GitHub REST id of the "Linked to Hermes" comment Hermes posts when the
    # issue is linked or created. Kept so `unlink_github_issue/1` can delete
    # that exact comment via `DELETE /issues/comments/{id}` (the endpoint is
    # keyed by comment id, not issue) — leaving no residue on GitHub.
    #
    # Nullable: issues linked before this feature, or when the best-effort
    # comment post failed, have no id; deletion then no-ops. The
    # `<!-- hermes:link:N -->` marker in the comment body is the human/fallback
    # recognizer; this id is the primary delete key.
    field :link_comment_id, :integer

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
    :last_sync_at,
    :link_comment_id
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
