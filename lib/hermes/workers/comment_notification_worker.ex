defmodule Hermes.Workers.CommentNotificationWorker do
  @moduledoc """
  Worker for sending email notifications when a comment is added to a request.

  Only notifies users explicitly mentioned via @handle in the comment content.
  The comment author is excluded from notifications to avoid self-notification.

  ## Usage

      %{comment_id: comment.id}
      |> Hermes.Workers.CommentNotificationWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 5,
    priority: 2

  require Logger

  alias Hermes.Notifications.Email
  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.RequestComment

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    Logger.info("Processing comment notification for comment #{comment_id}")

    comment =
      RequestComment
      |> Repo.get!(comment_id)
      |> Repo.preload([:user, request: [:requesting_team, :assigned_to_team, :created_by]])

    recipients = build_recipients(comment.content, comment.user_id)

    Email.send_comment_notification(comment, recipients)
  end

  defp build_recipients(content, commenter_user_id) do
    Requests.resolve_mentions(content)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&(&1.id == commenter_user_id))
  end
end
