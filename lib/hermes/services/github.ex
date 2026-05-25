defmodule Hermes.Services.GitHub do
  @moduledoc """
  Facade for the GitHub integration.

  Renders request payloads (title, body, labels) and dispatches to the
  configured adapter:

    * `Hermes.Services.GitHub.HTTP`     — real REST API (prod, staging)
    * `Hermes.Services.GitHub.InMemory` — Agent-backed fake (dev)

  Tests can also inject a Req plug via `:github_req_options` (HTTP adapter
  only) for tight-control HTTP stubs.
  """

  alias Hermes.Requests.GitHubIssue
  alias Hermes.Requests.Request

  require Logger

  @default_adapter Hermes.Services.GitHub.HTTP

  @doc """
  Returns the default `{owner, repo}` for new issues, or
  `{:error, :missing_config}`.
  """
  def default_target do
    cfg = config()
    owner = cfg[:owner] || in_memory_default(:owner)
    repo = cfg[:default_repo] || in_memory_default(:repo)

    cond do
      is_nil(owner) -> {:error, :missing_config}
      is_nil(repo) -> {:error, :missing_config}
      true -> {:ok, {owner, repo}}
    end
  end

  defp in_memory_default(:owner) do
    if adapter() == Hermes.Services.GitHub.InMemory, do: "dev-org", else: nil
  end

  defp in_memory_default(:repo) do
    if adapter() == Hermes.Services.GitHub.InMemory, do: "hermes-fake", else: nil
  end

  @doc """
  Creates a GitHub issue from a request.

  Options:
    * `:owner` — overrides the configured owner
    * `:repo`  — overrides the default repo (use for per-request repo)

  Returns `{:ok, %{owner, repo, number, url}}`.
  """
  def create_issue(%Request{} = request, opts \\ []) do
    case resolve_target(opts) do
      {:ok, {owner, repo}} ->
        Logger.info(
          "GitHub.create_issue request_id=#{request.id} target=#{owner}/#{repo} adapter=#{inspect(adapter())}"
        )

        payload = %{
          owner: owner,
          repo: repo,
          title: issue_title(request),
          body: render_body(request),
          labels: labels_for(request)
        }

        case adapter().create_issue(payload) do
          {:ok, %{number: number, url: url}} ->
            Logger.info(
              "GitHub.create_issue ok request_id=#{request.id} issue=#{owner}/#{repo}##{number}"
            )

            {:ok, %{owner: owner, repo: repo, number: number, url: url}}

          {:error, reason} = err ->
            Logger.warning(
              "GitHub.create_issue failed request_id=#{request.id} target=#{owner}/#{repo} reason=#{inspect(reason)}"
            )

            err
        end

      {:error, reason} = err ->
        Logger.warning(
          "GitHub.create_issue aborted request_id=#{request.id} reason=#{inspect(reason)}"
        )

        err
    end
  end

  @doc """
  Updates the linked GitHub issue's title and body.
  """
  def update_issue(%GitHubIssue{owner: owner, repo: repo, number: number}, %Request{} = request) do
    Logger.info("GitHub.update_issue request_id=#{request.id} issue=#{owner}/#{repo}##{number}")

    %{
      owner: owner,
      repo: repo,
      number: number,
      title: issue_title(request),
      body: render_body(request),
      labels: labels_for(request)
    }
    |> adapter().update_issue()
    |> log_result("update_issue", "#{owner}/#{repo}##{number}")
  end

  @doc """
  Sets the issue state. `state` is `:open` or `:closed`.
  """
  def set_issue_state(%GitHubIssue{owner: owner, repo: repo, number: number}, state, opts \\ [])
      when state in [:open, :closed] do
    reason = Keyword.get(opts, :reason)

    Logger.info(
      "GitHub.set_issue_state issue=#{owner}/#{repo}##{number} state=#{state} reason=#{inspect(reason)}"
    )

    ref = %{owner: owner, repo: repo, number: number}

    result =
      if reason in [:not_planned, :completed] do
        adapter().set_issue_state(ref, state, reason: reason)
      else
        adapter().set_issue_state(ref, state)
      end

    log_result(result, "set_issue_state", "#{owner}/#{repo}##{number}")
  end

  @doc """
  Adds a comment to the linked issue.
  """
  def create_comment(%GitHubIssue{owner: owner, repo: repo, number: number}, body)
      when is_binary(body) do
    Logger.info("GitHub.create_comment issue=#{owner}/#{repo}##{number} bytes=#{byte_size(body)}")

    %{owner: owner, repo: repo, number: number}
    |> adapter().create_comment(body)
    |> log_result("create_comment", "#{owner}/#{repo}##{number}")
  end

  @doc """
  Fetches a single issue. Used when linking an existing issue.

  Returns `{:ok, %{number, url, state}}`.
  """
  def get_issue(owner, repo, number) when is_integer(number) do
    Logger.info("GitHub.get_issue issue=#{owner}/#{repo}##{number}")

    owner
    |> adapter().get_issue(repo, number)
    |> log_result("get_issue", "#{owner}/#{repo}##{number}")
  end

  @doc "Returns the GraphQL node ID of an issue."
  def get_issue_node_id(owner, repo, number) when is_integer(number) do
    adapter().get_issue_node_id(owner, repo, number)
  end

  @doc """
  Removes a project item (the issue stays untouched). `project_id` defaults
  to the configured value.
  """
  def remove_item(item_id, opts \\ []) do
    project_id = Keyword.get(opts, :project_id) || project_id_or_default()

    if is_nil(project_id) or project_id == "" do
      {:error, :missing_project_config}
    else
      Logger.info("GitHub.remove_item project=#{project_id} item=#{item_id}")
      adapter().remove_item(project_id, item_id)
    end
  end

  @doc "Attach a child issue as a sub-issue of a parent issue."
  def add_sub_issue(parent_node_id, child_node_id) do
    Logger.info("GitHub.add_sub_issue parent=#{parent_node_id} child=#{child_node_id}")
    adapter().add_sub_issue(parent_node_id, child_node_id)
  end

  @doc "Detach a child issue from a parent issue."
  def remove_sub_issue(parent_node_id, child_node_id) do
    Logger.info("GitHub.remove_sub_issue parent=#{parent_node_id} child=#{child_node_id}")
    adapter().remove_sub_issue(parent_node_id, child_node_id)
  end

  @doc "Adds an issue to a Projects v2 board. Returns the project item id."
  def add_issue_to_project(content_node_id, project_id \\ nil) do
    project_id = project_id || project_id_or_default()

    if is_nil(project_id) or project_id == "" do
      {:error, :missing_project_config}
    else
      Logger.info("GitHub.add_issue_to_project project=#{project_id} content=#{content_node_id}")
      adapter().add_issue_to_project(project_id, content_node_id)
    end
  end

  @doc """
  Moves a project item to the column matching `option_id`. The project ID and
  status field ID default to env config.
  """
  def move_item(item_id, option_id, opts \\ []) do
    project_id = Keyword.get(opts, :project_id) || project_id_or_default()
    field_id = Keyword.get(opts, :field_id) || status_field_id_or_default()

    cond do
      is_nil(project_id) or project_id == "" ->
        {:error, :missing_project_config}

      is_nil(field_id) or field_id == "" ->
        {:error, :missing_status_field}

      true ->
        Logger.info("GitHub.move_item item=#{item_id} option=#{option_id}")

        adapter().move_item(project_id, item_id, field_id, option_id)
        |> log_result("move_item", item_id)
    end
  end

  @doc "Lists status options for the configured project."
  def list_status_options(opts \\ []) do
    project_id = Keyword.get(opts, :project_id) || project_id_or_default()
    field_id = Keyword.get(opts, :field_id) || status_field_id_or_default()

    cond do
      is_nil(project_id) or project_id == "" -> {:error, :missing_project_config}
      is_nil(field_id) or field_id == "" -> {:error, :missing_status_field}
      true -> adapter().list_status_options(project_id, field_id)
    end
  end

  defp project_id_or_default do
    config()[:project_id] ||
      if adapter() == Hermes.Services.GitHub.InMemory, do: "PVT_DEV", else: nil
  end

  defp status_field_id_or_default do
    config()[:status_field_id] ||
      if adapter() == Hermes.Services.GitHub.InMemory, do: "FIELD_STATUS", else: nil
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

  @doc """
  Returns the configured adapter module. Defaults to the HTTP adapter.
  """
  def adapter do
    Application.get_env(:hermes, :github_adapter, @default_adapter)
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
    |> add_label(epic_label_for(r))
    |> Enum.reject(&is_nil/1)
  end

  defp epic_label_for(%Request{is_epic: true, parent_id: nil}), do: "Epic"
  defp epic_label_for(_), do: nil

  defp add_label(list, nil), do: list
  defp add_label(list, label), do: [label | list]

  defp resolve_target(opts) do
    cfg = config()
    owner = Keyword.get(opts, :owner) || cfg[:owner] || in_memory_default(:owner)
    repo = Keyword.get(opts, :repo) || cfg[:default_repo] || in_memory_default(:repo)

    cond do
      is_nil(owner) -> {:error, :missing_config}
      is_nil(repo) -> {:error, :missing_config}
      true -> {:ok, {owner, repo}}
    end
  end

  defp config, do: Application.get_env(:hermes, :github, [])

  defp log_result({:ok, _} = ok, op, ref) do
    Logger.info("GitHub.#{op} ok issue=#{ref}")
    ok
  end

  defp log_result({:error, reason} = err, op, ref) do
    Logger.warning("GitHub.#{op} failed issue=#{ref} reason=#{inspect(reason)}")
    err
  end
end
