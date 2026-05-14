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
  def set_issue_state(%{owner: owner, repo: repo, number: number}, state)
      when state in [:open, :closed] do
    patch("/repos/#{owner}/#{repo}/issues/#{number}", %{"state" => Atom.to_string(state)})
  end

  @impl true
  def create_comment(%{owner: owner, repo: repo, number: number}, body) when is_binary(body) do
    post("/repos/#{owner}/#{repo}/issues/#{number}/comments", %{"body" => body})
  end

  @impl true
  def get_issue(owner, repo, number) when is_integer(number) do
    case get("/repos/#{owner}/#{repo}/issues/#{number}") do
      {:ok, %{"number" => n, "html_url" => url, "state" => state}} ->
        {:ok, %{number: n, url: url, state: state}}

      {:ok, other} ->
        {:error, {:unexpected_payload, other}}

      {:error, _} = err ->
        err
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
