defmodule HermesWeb.KanbanLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Kanbans

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:boards, list_boards(socket))
     |> assign(:page_title, "Kanban Boards")}
  end

  defp list_boards(socket) do
    current_user = socket.assigns[:current_user]
    Kanbans.list_boards_by_team(current_user.team_id)
  end
end
