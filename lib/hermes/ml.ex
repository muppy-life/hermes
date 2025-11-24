defmodule Hermes.ML do
  @moduledoc """
  Machine Learning module for loading and serving models.

  This module manages the lifecycle of ML models using Nx.Serving
  and provides a simple interface for text summarization.

  Models are loaded asynchronously in the background to avoid blocking
  application startup.
  """

  require Logger

  @doc """
  Check if the summarization model is ready to use.
  """
  def model_ready? do
    case Process.whereis(Hermes.Summarizer) do
      nil -> false
      _pid -> true
    end
  end

  @doc """
  Summarizes the given text.

  Returns {:error, :model_not_ready} if the model is still loading.

  ## Parameters
    * text - The text to summarize
    * opts - Optional keyword list with:
      * :max_length - Maximum length of the summary (default: 150)
      * :min_length - Minimum length of the summary (default: 40)

  ## Examples

      iex> Hermes.ML.summarize("Long text here...")
      {:ok, "Short summary"}

      iex> Hermes.ML.summarize("Long text", max_length: 100)
      {:ok, "Summary"}
  """
  def summarize(text, opts \\ []) when is_binary(text) do
    if not model_ready?() do
      Logger.warning("Summarization requested but model is still loading")
      {:error, :model_not_ready}
    else
      max_length = Keyword.get(opts, :max_length, 150)
      min_length = Keyword.get(opts, :min_length, 40)

      try do
        result =
          Nx.Serving.batched_run(Hermes.Summarizer, %{
            "text" => text,
            "max_length" => max_length,
            "min_length" => min_length
          })

        summary = extract_summary(result)
        {:ok, summary}
      rescue
        error ->
          Logger.error("Summarization failed: #{inspect(error)}")
          {:error, "Summarization failed: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Asynchronously summarizes text using an Oban worker.

  Returns {:ok, job} on success.

  ## Examples

      iex> Hermes.ML.summarize_async(request_id, "Long text...")
      {:ok, %Oban.Job{}}
  """
  def summarize_async(request_id, text, opts \\ []) do
    %{
      request_id: request_id,
      text: text,
      max_length: Keyword.get(opts, :max_length, 150),
      min_length: Keyword.get(opts, :min_length, 40)
    }
    |> Hermes.Workers.SummarizationWorker.new(queue: :media)
    |> Oban.insert()
  end

  defp extract_summary(%{results: [%{text: text}]}), do: text

  defp extract_summary(%{results: results}) when is_list(results) do
    Enum.map_join(results, " ", & &1.text)
  end

  defp extract_summary(_), do: "Summary unavailable"
end
