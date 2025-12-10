defmodule Hermes.Workers.ModelLoaderWorker do
  @moduledoc """
  Oban worker for loading ML models asynchronously.

  This worker loads the mT5-small multilingual model in the background
  so it doesn't block application startup. The model is loaded once and then
  served via Nx.Serving for all subsequent summarization requests.

  Uses google/mt5-small which has a Bumblebee-compatible tokenizer format.

  ## Usage

  Enqueue a model loading job:

      %{}
      |> Hermes.Workers.ModelLoaderWorker.new(queue: :media)
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    priority: 1

  require Logger

  # Use google/mt5-small which has compatible tokenizer format
  @model_repo "google/mt5-small"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting ML model loading in background...")

    try do
      # Check if model is already loaded
      case Process.whereis(Hermes.Summarizer) do
        nil ->
          # Model not loaded, load it now
          load_model()

        _pid ->
          # Model already loaded
          Logger.info("ML model already loaded and serving")
          :ok
      end
    rescue
      error ->
        Logger.error("Failed to load ML model: #{inspect(error)}")
        {:error, error}
    end
  end

  defp load_model do
    Logger.info("Loading #{@model_repo} multilingual summarization model...")

    {:ok, model_info} =
      Bumblebee.load_model(
        {:hf, @model_repo},
        module: Bumblebee.Text.T5,
        architecture: :for_conditional_generation
      )

    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model_repo})

    {:ok, generation_config} =
      Bumblebee.load_generation_config({:hf, @model_repo})

    # Override generation config for better summarization
    generation_config = %{
      generation_config
      | max_new_tokens: 64,
        min_new_tokens: 10
    }

    serving =
      Bumblebee.Text.generation(model_info, tokenizer, generation_config,
        compile: [batch_size: 1, sequence_length: 512],
        preallocate_params: true
      )

    # Start the serving process
    {:ok, _pid} =
      Nx.Serving.start_link(
        serving: serving,
        name: Hermes.Summarizer,
        batch_timeout: 100
      )

    Logger.info("ML model #{@model_repo} loaded successfully and now serving requests")
    :ok
  end
end
