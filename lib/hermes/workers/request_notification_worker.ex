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
    Logger.info("Sending creation notification for request: #{request.title}")
    # TODO: Implement actual notification logic (email, Slack, etc.)
    # Example: Hermes.Mailer.send_request_created_email(request)
    :ok
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
    Logger.info("Sending assignment notification for request: #{request.title} to team #{team_id}")
    # TODO: Implement actual notification logic
    :ok
  end

  defp send_notification(_request, type, _args) do
    Logger.warning("Unknown notification type: #{type}")
    {:discard, "Unknown notification type"}
  end
end
