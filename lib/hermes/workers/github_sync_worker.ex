defmodule Hermes.Workers.GitHubSyncWorker do
  @moduledoc """
  Syncs Hermes requests to GitHub issues.

  Actions:
    * `"update"`       — push title/body changes to the linked issue
    * `"project_move"` — move the project board card to match Hermes status
    * `"comment"`      — mirror a Hermes comment as a GitHub issue comment

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
  alias Hermes.Requests.GitHubStatusMapping
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

  defp handle("project_move", %{"request_id" => id, "status" => hermes_status}) do
    request = get_request(id)

    cond do
      is_nil(request) ->
        {:discard, "Request not found"}

      is_nil(request.github_issue) ->
        :ok

      is_nil(request.github_issue.project_item_id) ->
        Logger.info(
          "GitHubSyncWorker project_move skipped: issue not on project board for request #{id}"
        )

        :ok

      recently_from_webhook?(request.github_issue) ->
        Logger.info("GitHubSyncWorker project_move skipped: recent webhook update")
        :ok

      true ->
        case Repo.get_by(GitHubStatusMapping, hermes_status: hermes_status) do
          nil ->
            Logger.warning(
              "GitHubSyncWorker project_move skipped: no mapping for hermes_status=#{hermes_status}"
            )

            :ok

          mapping ->
            case GitHub.move_item(request.github_issue.project_item_id, mapping.github_option_id) do
              {:ok, _} ->
                mark_synced_from_hermes(request.github_issue, mapping.github_option_name)
                :ok

              {:error, reason} ->
                {:error, inspect(reason)}
            end
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

  defp get_request(id) do
    Requests.get_request_with_github_issue(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # Loop-prevention: skip pushing to GitHub if the last update arrived from
  # GitHub within this window. Keeps webhook + forward sync from ping-ponging.
  @recent_webhook_grace_seconds 30

  defp recently_from_webhook?(%GitHubIssue{
         last_sync_source: "webhook",
         last_sync_at: %DateTime{} = ts
       }) do
    DateTime.diff(DateTime.utc_now(), ts, :second) < @recent_webhook_grace_seconds
  end

  defp recently_from_webhook?(_), do: false

  defp mark_synced_from_hermes(%GitHubIssue{} = issue, option_name) do
    issue
    |> GitHubIssue.changeset(%{
      project_status: option_name,
      last_sync_source: "hermes",
      last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

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
