defmodule Hermes.Services.GitHub do
  @moduledoc """
  Service for the GitHub REST API.

  Creates and updates GitHub issues that mirror Hermes requests. Each
  Hermes request is linked to at most one `Hermes.Requests.GitHubIssue`
  row that stores the canonical `(owner, repo, number)` identity.

  When creating a new issue, the target repo defaults to
  `GITHUB_OWNER/GITHUB_DEFAULT_REPO`. The caller may override per request
  by passing `repo:` to `create_issue/2`.
  """

  alias Hermes.Requests.GitHubIssue
  alias Hermes.Requests.Request

  require Logger

  @api_version "2022-11-28"

  @doc """
  Returns the default `{owner, repo}` for new issues, or
  `{:error, :missing_config}`.
  """
  def default_target do
    cfg = config()

    case {cfg[:owner], cfg[:default_repo]} do
      {nil, _} -> {:error, :missing_config}
      {_, nil} -> {:error, :missing_config}
      {o, r} -> {:ok, {o, r}}
    end
  end

  @doc """
  Creates a GitHub issue from a request.

  Options:
    * `:owner` — overrides the configured owner
    * `:repo`  — overrides the default repo (use for per-request repo)

  Returns `{:ok, %{owner, repo, number, url}}`.
  """
  def create_issue(%Request{} = request, opts \\ []) do
    with {:ok, {owner, repo}} <- resolve_target(opts) do
      body = %{
        "title" => issue_title(request),
        "body" => render_body(request),
        "labels" => labels_for(request)
      }

      case post("/repos/#{owner}/#{repo}/issues", body) do
        {:ok, %{"number" => number, "html_url" => url}} ->
          {:ok, %{owner: owner, repo: repo, number: number, url: url}}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Updates the linked GitHub issue's title and body.
  """
  def update_issue(%GitHubIssue{owner: owner, repo: repo, number: number}, %Request{} = request) do
    body = %{
      "title" => issue_title(request),
      "body" => render_body(request),
      "labels" => labels_for(request)
    }

    patch("/repos/#{owner}/#{repo}/issues/#{number}", body)
  end

  @doc """
  Sets the issue state. `state` is `:open` or `:closed`.
  """
  def set_issue_state(%GitHubIssue{owner: owner, repo: repo, number: number}, state)
      when state in [:open, :closed] do
    patch("/repos/#{owner}/#{repo}/issues/#{number}", %{"state" => Atom.to_string(state)})
  end

  @doc """
  Adds a comment to the linked issue.
  """
  def create_comment(%GitHubIssue{owner: owner, repo: repo, number: number}, body)
      when is_binary(body) do
    post("/repos/#{owner}/#{repo}/issues/#{number}/comments", %{"body" => body})
  end

  @doc """
  Fetches a single issue. Used when linking an existing issue.
  """
  def get_issue(owner, repo, number) when is_integer(number) do
    get("/repos/#{owner}/#{repo}/issues/#{number}")
  end

  @doc """
  Parses an issue reference: full URL or bare number.

  Returns `{:ok, {owner, repo, number}}`. For bare numbers `owner`/`repo`
  are `nil` and the caller resolves with the default target.
  """
  def parse_issue_reference(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      match = Regex.run(~r{github\.com/([^/]+)/([^/]+)/issues/(\d+)}, value) ->
        [_, owner, repo, n] = match
        {:ok, {owner, repo, String.to_integer(n)}}

      match = Regex.run(~r{^#?(\d+)$}, value) ->
        [_, n] = match
        {:ok, {nil, nil, String.to_integer(n)}}

      true ->
        {:error, :invalid_reference}
    end
  end

  def parse_issue_reference(_), do: {:error, :invalid_reference}

  @doc """
  Renders the issue body markdown from a request.
  """
  def render_body(%Request{} = r) do
    sections =
      [
        section("Kind", r.kind && Request.kind_label(r.kind)),
        section("Priority", r.priority && Request.priority_label(r.priority)),
        section(
          "Target user",
          r.target_user_type && Request.target_user_label(r.target_user_type)
        ),
        section("Goal target", r.goal_target && Request.goal_target_label(r.goal_target)),
        section("Current situation", r.current_situation),
        section("Goal", r.goal_description),
        section("Data", r.data_description),
        section("Expected output", r.expected_output),
        section("Description", r.description)
      ]
      |> Enum.reject(&is_nil/1)

    footer = "\n\n---\n_Synced from Hermes request ##{r.id}_"

    Enum.join(sections, "\n\n") <> footer
  end

  defp section(_label, nil), do: nil
  defp section(_label, ""), do: nil
  defp section(label, value), do: "### #{label}\n\n#{value}"

  defp issue_title(%Request{title: title, id: id}) do
    base = title || "Hermes request"
    "[Hermes ##{id}] #{base}"
  end

  defp labels_for(%Request{} = r) do
    []
    |> add_label(
      r.priority && "priority:#{Request.priority_label(r.priority) |> String.downcase()}"
    )
    |> add_label(r.kind && "kind:#{r.kind}")
    |> Enum.reject(&is_nil/1)
  end

  defp add_label(list, nil), do: list
  defp add_label(list, label), do: [label | list]

  defp resolve_target(opts) do
    cfg = config()
    owner = Keyword.get(opts, :owner) || cfg[:owner]
    repo = Keyword.get(opts, :repo) || cfg[:default_repo]

    cond do
      is_nil(owner) -> {:error, :missing_config}
      is_nil(repo) -> {:error, :missing_config}
      true -> {:ok, {owner, repo}}
    end
  end

  # HTTP layer

  defp post(path, body), do: request(:post, path, json: body)
  defp patch(path, body), do: request(:patch, path, json: body)
  defp get(path), do: request(:get, path, [])

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

  defp config, do: Application.get_env(:hermes, :github, [])

  defp maybe_put_test_plug(opts) do
    case Application.get_env(:hermes, :github_req_options) do
      nil -> opts
      extra when is_list(extra) -> Keyword.merge(opts, extra)
    end
  end
end
