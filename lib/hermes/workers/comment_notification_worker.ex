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

  alias Hermes.Accounts
  alias Hermes.Notifications.Email
  alias Hermes.Repo
  alias Hermes.Requests.RequestComment

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"comment_id" => comment_id} = args}) do
    Logger.info("Processing comment notification for comment #{comment_id}")

    comment =
      RequestComment
      |> Repo.get!(comment_id)
      |> Repo.preload([:user, request: [:requesting_team, :assigned_to_team, :created_by]])

    exclude_user_ids = Map.get(args, "exclude_user_ids", [])
    recipients = build_recipients(comment.content, comment.user_id, exclude_user_ids)

    Email.send_comment_notification(comment, recipients)
  end

  defp build_recipients(content, commenter_user_id, exclude_user_ids) do
    mentioned_prefixes = extract_mention_prefixes(content)

    Accounts.list_users_by_email_prefixes(mentioned_prefixes)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&(&1.id == commenter_user_id || &1.id in exclude_user_ids))
  end

  defp extract_mention_prefixes(content) do
    ~r/@([\w.-]+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_full, handle] -> String.downcase(handle) end)
    |> Enum.uniq()
  end
end
