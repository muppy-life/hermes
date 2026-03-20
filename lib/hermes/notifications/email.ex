defmodule Hermes.Notifications.Email do
  @moduledoc """
  Email notification module for sending transactional emails via SendGrid.

  Builds typed email payloads and delegates delivery to `Hermes.Notifications.Mailer`.

  ## Usage

      Hermes.Notifications.Email.send_comment_notification(comment, recipients)
      Hermes.Notifications.Email.send_request_created_notification(request, recipients)
  """

  require Logger

  alias Hermes.Notifications.Mailer

  @from_email %{email: "no-reply@muppy.com", name: "Muppy"}

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

      to_emails = Enum.map(recipients, &%{email: &1.email})

      payload = %{
        from: @from_email,
        personalizations: [
          %{
            to: to_emails,
            dynamic_template_data: build_comment_template_data(comment)
          }
        ],
        template_id: comment_notification_template_id()
      }

      Mailer.deliver(payload)
    end
  end

  @doc """
  Sends a request creation notification email to the assigned team and the request creator.

  ## Parameters

    * `request` - The `%Hermes.Requests.Request{}` struct with `:requesting_team`,
      `:assigned_to_team`, and `:created_by` preloaded
    * `recipients` - List of `%Hermes.Accounts.User{}` structs to notify

  ## Returns

    * `:ok` on success or when there are no recipients
    * `{:error, reason}` on failure
  """
  def send_request_created_notification(request, recipients) when is_list(recipients) do
    if recipients == [] do
      Logger.debug("No recipients for request created notification on request #{request.id}")
      :ok
    else
      Logger.info(
        "Sending request created notification for request #{request.id} to #{length(recipients)} recipient(s)"
      )

      to_emails = Enum.map(recipients, &%{email: &1.email})

      payload = %{
        from: @from_email,
        personalizations: [
          %{
            to: to_emails,
            dynamic_template_data: build_request_created_template_data(request)
          }
        ],
        template_id: request_created_template_id()
      }

      Mailer.deliver(payload)
    end
  end

  defp build_comment_template_data(%{request: request} = comment) do
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

  defp build_request_created_template_data(request) do
    %{
      request_id: request.id,
      request_title: request.title,
      request_status: request.status,
      request_priority: request.priority,
      requesting_team: request.requesting_team && request.requesting_team.name,
      assigned_team: request.assigned_to_team && request.assigned_to_team.name,
      created_by_email: request.created_by && request.created_by.email
    }
  end

  defp comment_notification_template_id, do: "SENDGRID_COMMENT_TEMPLATE_ID"
  defp request_created_template_id, do: "SENDGRID_REQUEST_CREATED_TEMPLATE_ID"
end
