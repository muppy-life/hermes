defmodule Hermes.Notifications.Mailer do
  @moduledoc """
  Low-level SendGrid delivery module.

  Handles raw HTTP communication with the SendGrid API.
  Use `Hermes.Notifications.Email` to build and send typed email notifications.

  ## Configuration

  The following environment variables are expected:

    * `SENDGRID_API_KEY` - Your SendGrid API key
  """

  require Logger

  @base_url "https://api.sendgrid.com/v3/mail/send"

  @doc """
  Delivers a pre-built SendGrid payload via the API.
  """
  def deliver(payload) do
    case Req.post(@base_url, json: Jason.encode!(payload), headers: headers()) do
      {:ok, %{status_code: 202}} -> {:ok, "Email sent"}
      val -> handle_error(val)
    end
  end

  def api_key, do: Application.get_env(:caronte, SendGrid)[:api_key]

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp handle_error({:ok, %{status_code: code, body: body}}) do
    Logger.error("#{__MODULE__} Error #{code} when sending email:")

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
end
