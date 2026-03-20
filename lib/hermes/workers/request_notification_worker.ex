defmodule Hermes.Workers.RequestNotificationWorker do
  @moduledoc """
  Worker for sending notifications about request updates asynchronously.

  This worker handles sending notifications (email, slack, etc.) when
  requests are created, updated, or change status.

  ## Usage

  Send notification when a request is created:

      %{request_id: request.id, type: "created"}
      |> Hermes.Workers.RequestNotificationWorker.new()
      |> Oban.insert()

  Send notification when a request status changes:

      %{request_id: request.id, type: "status_changed", old_status: "pending", new_status: "in_progress"}
      |> Hermes.Workers.RequestNotificationWorker.new(queue: :events)
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 5,
    priority: 1

  require Logger

  alias Hermes.Accounts
  alias Hermes.Notifications.Email
  alias Hermes.Requests

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id, "type" => type} = args}) do
    Logger.info("Processing notification for request #{request_id}, type: #{type}")

    try do
      request = Requests.get_request!(request_id)
      send_notification(request, type, args)
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Request #{request_id} not found")
        {:discard, "Request not found"}
    end
  end

  defp send_notification(request, "created", _args) do
    recipients = build_created_recipients(request)
    Email.send_request_created_notification(request, recipients)
  end

  defp send_notification(request, "status_changed", %{
         "old_status" => old_status,
         "new_status" => new_status
       }) do
    Logger.info(
      "Sending status change notification for request: #{request.title} (#{old_status} -> #{new_status})"
    )

    # TODO: Implement actual notification logic
    :ok
  end

  defp send_notification(request, "assigned", %{"team_id" => team_id}) do
    Logger.info(
      "Sending assignment notification for request: #{request.title} to team #{team_id}"
    )

    # TODO: Implement actual notification logic
    :ok
  end

  defp send_notification(_request, type, _args) do
    Logger.warning("Unknown notification type: #{type}")
    {:discard, "Unknown notification type"}
  end

  defp build_created_recipients(request) do
    requesting_team_users =
      if request.requesting_team_id,
        do: Accounts.list_users_by_team(request.requesting_team_id),
        else: []

    assigned_team_users =
      if request.assigned_to_team_id,
        do: Accounts.list_users_by_team(request.assigned_to_team_id),
        else: []

    creator = if request.created_by, do: request.created_by, else: %{id: nil}

    (requesting_team_users ++ assigned_team_users)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&(&1.id == creator.id))
  end
end
