defmodule Hermes.Notifications.Email do
  @moduledoc """
  Email notification module for sending transactional emails via SendGrid.

  This module provides functions for sending email notifications. The actual
  SendGrid API integration is handled by the placeholder functions below,
  which should be replaced with the real implementation once the SendGrid
  template IDs and API credentials are configured.

  ## Configuration

  The following environment variables are expected:

    * `SENDGRID_API_KEY` - Your SendGrid API key
    * `SENDGRID_FROM_EMAIL` - The sender email address (e.g. "noreply@yourapp.com")
    * `SENDGRID_COMMENT_TEMPLATE_ID` - SendGrid dynamic template ID for comment notifications

  ## Usage

      Hermes.Notifications.Email.send_comment_notification(comment, recipients)
  """

  require Logger

  @doc """
  Sends a comment notification email to all involved parties on a request.

  Recipients typically include members of the requesting team, members of
  the assigned team, and the request creator.

  The email content (subject, body, layout) is managed by the SendGrid
  dynamic template. This function passes the relevant data as template
  variables.

  ## Parameters

    * `comment` - The `%Hermes.Requests.RequestComment{}` struct with `:user` and
      `:request` (including `:requesting_team`, `:assigned_to_team`, `:created_by`) preloaded
    * `recipients` - List of `%Hermes.Accounts.User{}` structs to notify

  ## Returns

    * `:ok` on success or when there are no recipients
    * `{:error, reason}` on failure
  """
  def send_comment_notification(comment, recipients) when is_list(recipients) do
    if recipients == [] do
      Logger.debug("No recipients for comment notification #{comment.id}")
      :ok
    else
      Logger.info(
        "Sending comment notification for comment #{comment.id} to #{length(recipients)} recipient(s)"
      )

      do_send_comment_notification(comment, recipients)
    end
  end

  defp do_send_comment_notification(comment, recipients) do
    to_emails = Enum.map(recipients, &%{email: &1.email})

    template_data = build_template_data(comment)

    payload = %{
      from: %{
        email: "no-reply@muppy.com",
        name: "Muppy"
      },
      personalizations: [
        %{
          to: to_emails,
          dynamic_template_data: template_data
        }
      ],
      template_id: comment_notification_template_id()
    }

    send_api_request(payload)
  end

  defp build_template_data(%{request: request} = comment) do
    %{
      request_id: request.id,
      request_title: request.title,
      request_status: request.status,
      request_priority: request.priority,
      requesting_team: request.requesting_team && request.requesting_team.name,
      assigned_team: request.assigned_to_team && request.assigned_to_team.name,
      created_by_email: request.created_by && request.created_by.email,
      comment_author_email: comment.user.email,
      comment_content: comment.content,
      comment_inserted_at: comment.inserted_at
    }
  end

  defp comment_notification_template_id, do: "SENDGRID_COMMENT_TEMPLATE_ID"

  defp send_api_request(payload) do
    case Req.post(base_url(), json: Jason.encode!(payload), headers: headers()) do
      {:ok, %{status_code: 202}} -> {:ok, "Email sent"}
      val -> manage_send_grid_error(val)
    end
  end

  defp manage_send_grid_error({:ok, %{status_code: code, body: body}}) do
    Logger.error("#{__MODULE__} Error #{code} when sending email request:")

    body
    |> Jason.decode!()
    |> then(&Map.get(&1, "errors"))
    |> Enum.map(fn err ->
      err_msg = Map.get(err, "message")
      Logger.error(err_msg)
      err_msg
    end)
    |> Enum.reduce(fn err, errors -> err <> ", " <> errors end)
    |> then(&{:error, &1})
  end

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]
  end

  def api_key, do: Application.get_env(:caronte, SendGrid)[:api_key]
  defp base_url, do: "https://api.sendgrid.com/v3/mail/send"
end
