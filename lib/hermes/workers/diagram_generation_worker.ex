defmodule Hermes.Workers.DiagramGenerationWorker do
  @moduledoc """
  Oban worker for generating Mermaid diagrams asynchronously using Claude API.

  This worker generates a visual diagram representing the solution flow
  based on the request's goal description and expected output.

  ## Usage

  Enqueue a diagram generation job:

      %{
        request_id: 1
      }
      |> Hermes.Workers.DiagramGenerationWorker.new(queue: :default)
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    priority: 2

  require Logger
  alias Hermes.Requests
  alias Hermes.Services.Claude

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    request_id = args["request_id"]

    Logger.info("Starting diagram generation for request #{request_id} (attempt #{attempt})")

    try do
      request = Requests.get_request!(request_id)

      # Build the prompt for Claude
      prompt = build_diagram_prompt(request)

      # Generate the diagram using Claude API
      case Claude.ask(prompt, model: "claude-sonnet-4-20250514", max_tokens: 2048, system: diagram_system_prompt()) do
        {:ok, diagram} ->
          # Clean up the diagram
          cleaned_diagram = clean_diagram(diagram)

          # Store the diagram in the request
          case Requests.update_request(request, %{solution_diagram: cleaned_diagram}) do
            {:ok, _request} ->
              Logger.info("Diagram generation completed for request #{request_id}")

              # Broadcast update to any LiveView subscribed to this request
              Phoenix.PubSub.broadcast(
                Hermes.PubSub,
                "request:#{request_id}",
                {:diagram_generated, request_id}
              )

              :ok

            {:error, reason} ->
              Logger.error("Failed to store diagram for request #{request_id}: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, "ANTHROPIC_API_KEY not configured" = reason} ->
          Logger.warning("Claude API key not configured for request #{request_id}")
          {:discard, reason}

        {:error, reason} ->
          Logger.error("Diagram generation failed for request #{request_id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Request #{request_id} not found")
        {:discard, "Request not found"}

      error ->
        Logger.error("Diagram generation failed for request #{request_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp build_diagram_prompt(request) do
    """
    Based on the following information, create a Mermaid flowchart diagram that visualizes the solution flow from current state to desired output.

    **Request Type:** #{Hermes.Requests.Request.kind_label(request.kind)}

    **Target Users:** #{Hermes.Requests.Request.target_user_label(request.target_user_type)}

    **Current Situation:**
    #{request.current_situation}

    **Goal Description:**
    #{request.goal_description}

    **Expected Output Type:** #{Hermes.Requests.Request.goal_target_label(request.goal_target)}

    **Expected Output Details:**
    #{request.expected_output}

    #{if request.data_description, do: "**Related Data:**\n#{request.data_description}", else: ""}

    Please create a clear, well-organized Mermaid flowchart that:
    1. Shows the current state/problem
    2. Visualizes the key steps or components of the solution
    3. Shows the expected output/result
    4. Uses appropriate shapes (rectangles for processes, diamonds for decisions, etc.)
    5. Keeps it simple and focused on the main flow

    Return ONLY the Mermaid diagram code, starting with 'flowchart' or 'graph'. Do not include markdown code fences or any explanatory text.
    """
  end

  defp diagram_system_prompt do
    """
    You are a technical diagram expert. Generate clean, clear Mermaid diagrams that effectively communicate solution flows.
    Focus on clarity and simplicity. Use standard Mermaid flowchart syntax.
    Return only the Mermaid code without any markdown formatting or explanations.
    """
  end

  defp clean_diagram(diagram) do
    diagram
    |> String.trim()
    # Remove markdown code fences if present
    |> String.replace(~r/```mermaid\s*/i, "")
    |> String.replace(~r/```\s*/, "")
    # Remove any extra whitespace
    |> String.trim()
  end
end
