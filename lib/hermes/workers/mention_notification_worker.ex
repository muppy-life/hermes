defmodule Hermes.Workers.MentionNotificationWorker do
  @moduledoc """
  Worker for handling mention notifications when a user is @mentioned in a comment.

  Creates a persistent in-app notification record for the mentioned user.
  The commenter is never notified of their own mentions.

  ## Usage

      %{comment_id: comment.id, mentioned_user_id: user.id}
      |> Hermes.Workers.MentionNotificationWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 5,
    priority: 1

  require Logger

  alias Hermes.Accounts
  alias Hermes.Notifications
  alias Hermes.Repo
  alias Hermes.Requests.RequestComment

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"comment_id" => comment_id, "mentioned_user_id" => mentioned_user_id}
      }) do
    Logger.info(
      "Processing mention notification for comment #{comment_id}, user #{mentioned_user_id}"
    )

    comment =
      RequestComment
      |> Repo.get!(comment_id)
      |> Repo.preload([:user, request: [:requesting_team, :assigned_to_team, :created_by]])

    mentioned_user = Accounts.get_user!(mentioned_user_id)

    Notifications.create_mention_notification(
      mentioned_user.id,
      comment,
      comment.user_id
    )
  end
end
