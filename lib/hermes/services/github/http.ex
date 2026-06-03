defmodule Hermes.Services.GitHub.HTTP do
  @moduledoc """
  GitHub adapter that calls the real REST API.
  """

  @behaviour Hermes.Services.GitHub.Adapter

  require Logger

  @api_version "2022-11-28"

  @impl true
  def create_issue(%{owner: owner, repo: repo, title: title, body: body, labels: labels}) do
    case post("/repos/#{owner}/#{repo}/issues", %{
           "title" => title,
           "body" => body,
           "labels" => labels
         }) do
      {:ok, %{"number" => number, "html_url" => url}} ->
        {:ok, %{number: number, url: url}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def update_issue(%{
        owner: owner,
        repo: repo,
        number: number,
        title: title,
        body: body,
        labels: labels
      }) do
    patch("/repos/#{owner}/#{repo}/issues/#{number}", %{
      "title" => title,
      "body" => body,
      "labels" => labels
    })
  end

  @impl true
  def set_issue_title(%{owner: owner, repo: repo, number: number}, title)
      when is_binary(title) do
    patch("/repos/#{owner}/#{repo}/issues/#{number}", %{"title" => title})
  end

  @impl true
  def set_issue_state(issue_ref, state) when state in [:open, :closed] do
    set_issue_state(issue_ref, state, [])
  end

  @impl true
  def set_issue_state(%{owner: owner, repo: repo, number: number}, state, opts)
      when state in [:open, :closed] do
    body = %{"state" => Atom.to_string(state)}

    body =
      case Keyword.get(opts, :reason) do
        :not_planned -> Map.put(body, "state_reason", "not_planned")
        :completed -> Map.put(body, "state_reason", "completed")
        _ -> body
      end

    patch("/repos/#{owner}/#{repo}/issues/#{number}", body)
  end

  @impl true
  def create_comment(%{owner: owner, repo: repo, number: number}, body) when is_binary(body) do
    post("/repos/#{owner}/#{repo}/issues/#{number}/comments", %{"body" => body})
  end

  @impl true
  def delete_comment(%{owner: owner, repo: repo}, comment_id) when is_integer(comment_id) do
    delete("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}")
  end

  @impl true
  def get_issue(owner, repo, number) when is_integer(number) do
    case get("/repos/#{owner}/#{repo}/issues/#{number}") do
      {:ok, %{"number" => n, "html_url" => url, "state" => state} = issue} ->
        {:ok, %{number: n, url: url, state: state, title: Map.get(issue, "title", "")}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def get_issue_node_id(owner, repo, number) when is_integer(number) do
    case get("/repos/#{owner}/#{repo}/issues/#{number}") do
      {:ok, %{"node_id" => node_id}} -> {:ok, node_id}
      {:ok, other} -> {:error, {:unexpected_payload, other}}
      {:error, _} = err -> err
    end
  end

  @impl true
  def add_issue_to_project(project_id, content_node_id) do
    query = """
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
        item { id }
      }
    }
    """

    case graphql(query, %{"projectId" => project_id, "contentId" => content_node_id}) do
      {:ok, %{"data" => %{"addProjectV2ItemById" => %{"item" => %{"id" => id}}}}} ->
        {:ok, id}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def move_item(project_id, item_id, field_id, option_id) do
    query = """
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $projectId,
        itemId: $itemId,
        fieldId: $fieldId,
        value: { singleSelectOptionId: $optionId }
      }) {
        projectV2Item { id }
      }
    }
    """

    case graphql(query, %{
           "projectId" => project_id,
           "itemId" => item_id,
           "fieldId" => field_id,
           "optionId" => option_id
         }) do
      {:ok, %{"data" => %{"updateProjectV2ItemFieldValue" => %{"projectV2Item" => item}}}} ->
        {:ok, item}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def list_status_options(_project_id, field_id) do
    # The Projects v2 GraphQL schema does not support `ProjectV2.field(id:)`,
    # but the status field has its own GraphQL node ID we can fetch directly.
    query = """
    query($fieldId: ID!) {
      node(id: $fieldId) {
        ... on ProjectV2SingleSelectField {
          options { id name }
        }
      }
    }
    """

    case graphql(query, %{"fieldId" => field_id}) do
      {:ok, %{"data" => %{"node" => %{"options" => options}}}} ->
        {:ok, Enum.map(options, fn %{"id" => id, "name" => name} -> %{id: id, name: name} end)}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def find_project_item(project_id, issue_node_id) do
    query = """
    query($issueId: ID!) {
      node(id: $issueId) {
        ... on Issue {
          projectItems(first: 50) {
            nodes { id project { id } }
          }
        }
      }
    }
    """

    case graphql(query, %{"issueId" => issue_node_id}) do
      {:ok, %{"data" => %{"node" => %{"projectItems" => %{"nodes" => nodes}}}}} ->
        match =
          Enum.find(nodes, fn item ->
            get_in(item, ["project", "id"]) == project_id
          end)

        {:ok, match && match["id"]}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def remove_item(project_id, item_id) do
    query = """
    mutation($projectId: ID!, $itemId: ID!) {
      deleteProjectV2Item(input: {projectId: $projectId, itemId: $itemId}) {
        deletedItemId
      }
    }
    """

    case graphql(query, %{"projectId" => project_id, "itemId" => item_id}) do
      {:ok, %{"data" => %{"deleteProjectV2Item" => result}}} -> {:ok, result}
      {:ok, %{"errors" => errors}} -> {:error, {:graphql_error, errors}}
      {:ok, other} -> {:error, {:unexpected_payload, other}}
      {:error, _} = err -> err
    end
  end

  @impl true
  def add_sub_issue(parent_node_id, child_node_id) do
    query = """
    mutation($issueId: ID!, $subIssueId: ID!) {
      addSubIssue(input: {issueId: $issueId, subIssueId: $subIssueId}) {
        subIssue { id number }
      }
    }
    """

    case graphql(query, %{"issueId" => parent_node_id, "subIssueId" => child_node_id}) do
      {:ok, %{"data" => %{"addSubIssue" => result}}} -> {:ok, result}
      {:ok, %{"errors" => errors}} -> {:error, {:graphql_error, errors}}
      {:ok, other} -> {:error, {:unexpected_payload, other}}
      {:error, _} = err -> err
    end
  end

  @impl true
  def sub_issue_attached?(parent_node_id, child_node_id) do
    query = """
    query($issueId: ID!) {
      node(id: $issueId) {
        ... on Issue {
          subIssues(first: 100) { nodes { id } }
        }
      }
    }
    """

    case graphql(query, %{"issueId" => parent_node_id}) do
      {:ok, %{"data" => %{"node" => %{"subIssues" => %{"nodes" => nodes}}}}} ->
        {:ok, Enum.any?(nodes, &(&1["id"] == child_node_id))}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def list_sub_issues(parent_node_id) do
    query = """
    query($issueId: ID!) {
      node(id: $issueId) {
        ... on Issue {
          subIssues(first: 100) {
            nodes {
              id
              number
              title
              state
              url
              repository { name owner { login } }
            }
          }
        }
      }
    }
    """

    case graphql(query, %{"issueId" => parent_node_id}) do
      {:ok, %{"data" => %{"node" => %{"subIssues" => %{"nodes" => nodes}}}}} ->
        {:ok, Enum.map(nodes, &decode_sub_issue/1)}

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_error, errors}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
    end
  end

  defp decode_sub_issue(node) do
    %{
      node_id: node["id"],
      number: node["number"],
      title: node["title"],
      # GraphQL issue state is uppercase ("OPEN"/"CLOSED"); REST uses lowercase.
      state: node["state"] |> to_string() |> String.downcase(),
      url: node["url"],
      owner: get_in(node, ["repository", "owner", "login"]),
      repo: get_in(node, ["repository", "name"])
    }
  end

  @impl true
  def remove_sub_issue(parent_node_id, child_node_id) do
    query = """
    mutation($issueId: ID!, $subIssueId: ID!) {
      removeSubIssue(input: {issueId: $issueId, subIssueId: $subIssueId}) {
        subIssue { id }
      }
    }
    """

    case graphql(query, %{"issueId" => parent_node_id, "subIssueId" => child_node_id}) do
      {:ok, %{"data" => %{"removeSubIssue" => result}}} -> {:ok, result}
      {:ok, %{"errors" => errors}} -> {:error, {:graphql_error, errors}}
      {:ok, other} -> {:error, {:unexpected_payload, other}}
      {:error, _} = err -> err
    end
  end

  # HTTP layer

  defp post(path, body), do: request(:post, path, json: body)
  defp patch(path, body), do: request(:patch, path, json: body)
  defp get(path), do: request(:get, path, [])
  defp delete(path), do: request(:delete, path, [])

  defp request(method, path, opts) do
    cfg = config()
    token = cfg[:token]

    if is_nil(token) or token == "" do
      {:error, :missing_token}
    else
      url = cfg[:api_url] <> path

      headers = [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/vnd.github+json"},
        {"x-github-api-version", @api_version},
        {"user-agent", "hermes-app"}
      ]

      opts =
        [headers: headers, retry: false]
        |> Keyword.merge(opts)
        |> maybe_put_test_plug()

      case apply(Req, method, [url, opts]) do
        {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
          {:ok, resp_body}

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          Logger.warning("GitHub #{method} #{path} -> #{status}: #{inspect(resp_body)}")
          {:error, {:http_error, status, resp_body}}

        {:error, reason} ->
          Logger.warning("GitHub #{method} #{path} transport error: #{inspect(reason)}")
          {:error, {:transport_error, reason}}
      end
    end
  end

  defp graphql(query, variables) do
    cfg = config()
    token = cfg[:token]
    url = cfg[:graphql_url] || "https://api.github.com/graphql"

    if is_nil(token) or token == "" do
      {:error, :missing_token}
    else
      headers = [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/vnd.github+json"},
        {"content-type", "application/json"},
        {"user-agent", "hermes-app"}
      ]

      body = %{"query" => query, "variables" => variables}

      opts =
        [headers: headers, retry: false, json: body]
        |> maybe_put_test_plug()

      case Req.post(url, opts) do
        {:ok, %Req.Response{status: 200, body: resp}} ->
          {:ok, resp}

        {:ok, %Req.Response{status: status, body: resp}} ->
          Logger.warning("GitHub GraphQL -> #{status}: #{inspect(resp)}")
          {:error, {:http_error, status, resp}}

        {:error, reason} ->
          Logger.warning("GitHub GraphQL transport error: #{inspect(reason)}")
          {:error, {:transport_error, reason}}
      end
    end
  end

  defp config, do: Application.get_env(:hermes, :github, [])

  defp maybe_put_test_plug(opts) do
    case Application.get_env(:hermes, :github_req_options) do
      nil -> opts
      extra when is_list(extra) -> Keyword.merge(opts, extra)
    end
  end
end
