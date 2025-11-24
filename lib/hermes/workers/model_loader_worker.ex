defmodule Hermes.Workers.ModelLoaderWorker do
  @moduledoc """
  Oban worker for loading ML models asynchronously.

  This worker loads the mT5 multilingual summarization model in the background
  so it doesn't block application startup. The model is loaded once and then
  served via Nx.Serving for all subsequent summarization requests.

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
    Logger.info("Loading mT5 multilingual summarization model...")

    {:ok, model_info} =
      Bumblebee.load_model(
        {:hf, "csebuetnlp/mT5_multilingual_XLSum"},
        module: Bumblebee.Text.T5,
        architecture: :for_conditional_generation
      )

    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "csebuetnlp/mT5_multilingual_XLSum"})

    {:ok, generation_config} =
      Bumblebee.load_generation_config({:hf, "csebuetnlp/mT5_multilingual_XLSum"})

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

    Logger.info("ML model loaded successfully and now serving requests")
    :ok
  end
end
