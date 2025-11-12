defmodule HermesWeb.NavigationHistory do
  @moduledoc """
  Handles navigation history for LiveView back buttons.
  Stores the previous path in assigns for use in back navigation.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [get_connect_params: 1, connected?: 1]

  @doc """
  Assigns the return path based on the live_referer or provides a default fallback.
  Should be called in the mount or handle_params callback of LiveViews.

  ## Examples

      def mount(params, session, socket) do
        socket = assign_return_path(socket, default: ~p"/dashboard")
        {:ok, socket}
      end
  """
  def assign_return_path(socket, opts \\ []) do
    default = Keyword.get(opts, :default, "/")

    return_to =
      if connected?(socket) do
        # Try to get the _live_referer from connect params
        case get_connect_params(socket) do
          %{"_live_referer" => referer} when is_binary(referer) and referer != "undefined" ->
            extract_path_from_referer(referer)
          _ ->
            # Fallback to default
            default
        end
      else
        default
      end

    assign(socket, :return_to, return_to)
  end

  @doc """
  Extracts the path from a full referer URL.

  ## Examples

      iex> HermesWeb.NavigationHistory.extract_path_from_referer("http://localhost:4000/boards")
      "/boards"

      iex> HermesWeb.NavigationHistory.extract_path_from_referer("http://example.com/requests?status=new")
      "/requests?status=new"
  """
  def extract_path_from_referer(referer) when is_binary(referer) do
    case URI.parse(referer) do
      %URI{path: path, query: nil} when is_binary(path) -> path
      %URI{path: path, query: query} when is_binary(path) and is_binary(query) ->
        path <> "?" <> query
      %URI{path: path} when is_binary(path) ->
        path
      _ ->
        "/"
    end
  end

  def extract_path_from_referer(_), do: "/"
end
