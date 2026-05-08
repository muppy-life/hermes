defmodule Hermes.Workers.GitHubSyncWorker do
  @moduledoc """
  Syncs Hermes requests to GitHub issues.

  Actions:
    * `"create"`  — create a new issue, persist number+url on the request
    * `"update"`  — push title/body changes to the linked issue
    * `"status"`  — open/close based on Hermes status
    * `"comment"` — mirror a Hermes comment as a GitHub issue comment
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 5,
    priority: 2

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.Request
  alias Hermes.Requests.RequestComment
  alias Hermes.Services.GitHub

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => action} = args}) do
    if integration_configured?() do
      handle(action, args)
    else
      Logger.info("GitHub integration not configured; skipping #{action}")
      {:discard, "GitHub integration not configured"}
    end
  end

  defp handle("create", %{"request_id" => id}) do
    request = get_request(id)

    cond do
      is_nil(request) ->
        {:discard, "Request not found"}

      is_integer(request.github_issue_number) ->
        # Already linked, nothing to do.
        :ok

      true ->
        case GitHub.create_issue(request) do
          {:ok, %{number: number, url: url}} ->
            persist_issue_link(request, number, url)
            :ok

          {:error, reason} ->
            {:error, inspect(reason)}
        end
    end
  end

  defp handle("update", %{"request_id" => id}) do
    request = get_request(id)

    cond do
      is_nil(request) -> {:discard, "Request not found"}
      is_nil(request.github_issue_number) -> :ok
      true -> wrap(GitHub.update_issue(request))
    end
  end

  defp handle("status", %{"request_id" => id, "status" => status}) do
    request = get_request(id)

    cond do
      is_nil(request) ->
        {:discard, "Request not found"}

      is_nil(request.github_issue_number) ->
        :ok

      true ->
        case state_for_status(status) do
          nil -> :ok
          state -> wrap(GitHub.set_issue_state(request, state))
        end
    end
  end

  defp handle("comment", %{"comment_id" => comment_id}) do
    comment = Repo.get(RequestComment, comment_id) |> Repo.preload(:user)

    cond do
      is_nil(comment) ->
        {:discard, "Comment not found"}

      true ->
        request = get_request(comment.request_id)

        cond do
          is_nil(request) -> {:discard, "Request not found"}
          is_nil(request.github_issue_number) -> :ok
          true -> wrap(GitHub.create_comment(request, format_comment(comment)))
        end
    end
  end

  defp handle(action, _args) do
    Logger.warning("GitHubSyncWorker unknown action: #{action}")
    {:discard, "Unknown action"}
  end

  defp wrap({:ok, _}), do: :ok
  defp wrap({:error, reason}), do: {:error, inspect(reason)}

  defp persist_issue_link(%Request{} = request, number, url) do
    from(r in Request, where: r.id == ^request.id)
    |> Repo.update_all(set: [github_issue_number: number, github_issue_url: url])
  end

  defp get_request(id) do
    Requests.get_request!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp state_for_status("completed"), do: :closed
  defp state_for_status("blocked"), do: nil
  defp state_for_status(_), do: :open

  defp format_comment(%RequestComment{user: user, content: content}) do
    author =
      case user do
        %{email: email} when is_binary(email) -> email
        _ -> "Hermes user"
      end

    "**#{author}** commented in Hermes:\n\n#{content}"
  end

  defp integration_configured? do
    cfg = Application.get_env(:hermes, :github, [])
    cfg[:token] not in [nil, ""] and cfg[:owner] not in [nil, ""]
  end
end
