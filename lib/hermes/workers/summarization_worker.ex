defmodule Hermes.Workers.SummarizationWorker do
  @moduledoc """
  Oban worker for performing text summarization asynchronously.

  This worker uses the mT5 multilingual model to summarize text
  and stores the result in the database.

  ## Usage

  Enqueue a summarization job:

      %{
        request_id: 1,
        text: "Long text to summarize...",
        max_length: 150,
        min_length: 40
      }
      |> Hermes.Workers.SummarizationWorker.new(queue: :media)
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 5,
    priority: 2

  require Logger
  alias Hermes.Requests

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    request_id = args["request_id"]
    text = args["text"]
    max_length = args["max_length"]
    min_length = args["min_length"]
    field_to_update = args["field_to_update"] || "description"

    Logger.info(
      "Starting summarization for request #{request_id}, updating field: #{field_to_update} (attempt #{attempt})"
    )

    try do
      request = Requests.get_request!(request_id)

      # Perform summarization
      case Hermes.ML.summarize(text, max_length: max_length, min_length: min_length) do
        {:ok, summary} ->
          # Clean up the summary
          cleaned_summary = clean_summary(summary)

          # Store the summary in the request
          case store_summary(request, cleaned_summary, field_to_update) do
            {:ok, _request} ->
              Logger.info("Summarization completed for request #{request_id}")
              :ok

            {:error, reason} ->
              Logger.error(
                "Failed to store summary for request #{request_id}: #{inspect(reason)}"
              )

              {:error, reason}
          end

        {:error, :model_not_ready} ->
          # Progressive retry delay: more time for model to download (2GB+)
          # Attempt 1: wait 60s, Attempt 2: wait 120s, Attempt 3: wait 180s
          snooze_time = attempt * 60

          Logger.info(
            "ML model not ready yet for request #{request_id}, will retry in #{snooze_time}s (attempt #{attempt})"
          )

          {:snooze, snooze_time}

        {:error, reason} ->
          Logger.error("Summarization failed for request #{request_id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Request #{request_id} not found")
        {:discard, "Request not found"}

      error ->
        Logger.error("Summarization failed for request #{request_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp clean_summary(summary) do
    summary
    |> String.trim()
    |> String.replace(~r/\n+/, " ")
    |> String.replace(~r/\s+/, " ")
  end

  defp store_summary(request, summary, "title") do
    # Update the title with the summary
    Requests.update_request(request, %{title: summary})
  end

  defp store_summary(request, summary, "description") do
    # Append the summary to the description
    updated_description = """
    #{request.description}

    ---
    **AI Summary:**
    #{summary}
    """

    Requests.update_request(request, %{description: updated_description})
  end

  defp store_summary(request, summary, _field) do
    # Default to description for unknown fields
    store_summary(request, summary, "description")
  end
end
