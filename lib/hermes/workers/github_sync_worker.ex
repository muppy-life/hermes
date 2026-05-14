defmodule Hermes.Workers.GitHubSyncWorker do
  @moduledoc """
  Syncs Hermes requests to GitHub issues.

  Actions:
    * `"update"`  — push title/body changes to the linked issue
    * `"status"`  — open/close based on Hermes status
    * `"comment"` — mirror a Hermes comment as a GitHub issue comment

  Issue creation runs synchronously via `Hermes.Requests.create_github_issue_for_request/2`.
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 5,
    priority: 2

  require Logger

  alias Hermes.Repo
  alias Hermes.Requests
  alias Hermes.Requests.GitHubIssue
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

  defp handle("update", %{"request_id" => id}) do
    request = get_request(id)

    cond do
      is_nil(request) -> {:discard, "Request not found"}
      is_nil(request.github_issue) -> :ok
      true -> wrap(GitHub.update_issue(request.github_issue, request), request)
    end
  end

  defp handle("status", %{"request_id" => id, "status" => status}) do
    request = get_request(id)

    cond do
      is_nil(request) ->
        {:discard, "Request not found"}

      is_nil(request.github_issue) ->
        :ok

      true ->
        case state_for_status(status) do
          nil ->
            :ok

          state ->
            result = GitHub.set_issue_state(request.github_issue, state)
            update_cached_state(request.github_issue, state)
            wrap(result, request)
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
          is_nil(request.github_issue) -> :ok
          true -> wrap(GitHub.create_comment(request.github_issue, format_comment(comment)))
        end
    end
  end

  defp handle(action, _args) do
    Logger.warning("GitHubSyncWorker unknown action: #{action}")
    {:discard, "Unknown action"}
  end

  defp wrap(result, request \\ nil)
  defp wrap({:ok, _}, request), do: touch_last_synced(request)
  defp wrap({:error, reason}, _), do: {:error, inspect(reason)}

  defp touch_last_synced(nil), do: :ok

  defp touch_last_synced(%{github_issue: nil}), do: :ok

  defp touch_last_synced(%{github_issue: %GitHubIssue{} = issue}) do
    issue
    |> Ecto.Changeset.change(last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()

    :ok
  end

  defp update_cached_state(%GitHubIssue{} = issue, state) do
    issue
    |> Ecto.Changeset.change(state: Atom.to_string(state))
    |> Repo.update()
  end

  defp get_request(id) do
    Requests.get_request_with_github_issue(id)
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
    case Hermes.Services.GitHub.adapter() do
      Hermes.Services.GitHub.InMemory ->
        true

      _ ->
        cfg = Application.get_env(:hermes, :github, [])
        cfg[:token] not in [nil, ""] and cfg[:owner] not in [nil, ""]
    end
  end
end
