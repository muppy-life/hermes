defmodule HermesWeb.GitHubWebhookController do
  use HermesWeb, :controller

  require Logger

  alias Hermes.Requests

  def create(conn, params) do
    event = get_req_header(conn, "x-github-event") |> List.first()
    delivery = get_req_header(conn, "x-github-delivery") |> List.first()
    Logger.info("GitHub webhook event=#{event} delivery=#{delivery}")

    case handle_event(event, params) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, reason} ->
        Logger.warning("GitHub webhook handler failed event=#{event} reason=#{inspect(reason)}")
        send_resp(conn, 422, "handler error")

      :ignored ->
        send_resp(conn, 200, "ignored")
    end
  end

  defp handle_event(
         "projects_v2_item",
         %{
           "action" => action,
           "projects_v2_item" => item
         } = payload
       )
       when action in ["edited", "reordered", "created"] do
    # Merge `changes` from the top-level payload into the item map so the
    # reverse-sync handler sees both the item and the field_value transition.
    enriched = Map.put(item, "changes", payload["changes"])
    Requests.handle_project_item_event(enriched)
  end

  defp handle_event("issues", %{"action" => action, "issue" => issue} = payload)
       when action in ["opened", "closed", "reopened", "edited"] do
    repo = payload["repository"] || %{}
    owner = get_in(repo, ["owner", "login"])
    repo_name = repo["name"]

    issue
    |> Map.put("owner", owner)
    |> Map.put("repo", repo_name)
    |> Requests.handle_issue_event()
  end

  defp handle_event("ping", _params), do: :ok

  defp handle_event(_event, _params), do: :ignored
end
