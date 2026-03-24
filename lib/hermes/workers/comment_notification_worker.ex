defmodule Hermes.Workers.CommentNotificationWorker do
  @moduledoc """
  Worker for sending email notifications when a comment is added to a request.

  Notifies all involved parties: members of the requesting team, members of
  the assigned team, and the request creator. The comment author is excluded
  from notifications to avoid self-notification.

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
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    Logger.info("Processing comment notification for comment #{comment_id}")

    comment =
      RequestComment
      |> Repo.get!(comment_id)
      |> Repo.preload([:user, request: [:requesting_team, :assigned_to_team, :created_by]])

    recipients = build_recipients(comment.request, comment.user_id)

    Email.send_comment_notification(comment, recipients)
  end

  defp build_recipients(request, commenter_user_id) do
    requesting_team_users =
      if request.requesting_team_id,
        do: Accounts.list_users_by_team(request.requesting_team_id),
        else: []

    assigned_team_users =
      if request.assigned_to_team_id,
        do: Accounts.list_users_by_team(request.assigned_to_team_id),
        else: []

    creator = if request.created_by, do: [request.created_by], else: []

    (requesting_team_users ++ assigned_team_users ++ creator)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&(&1.id == commenter_user_id))
  end
end
