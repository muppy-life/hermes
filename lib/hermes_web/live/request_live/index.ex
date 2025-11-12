defmodule HermesWeb.RequestLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Team Requests")
     |> assign(:teams, Accounts.list_teams())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    sort_by = safe_to_atom(params["sort_by"], :inserted_at)
    sort_order = safe_to_atom(params["sort_order"], :desc)
    filter_status = params["status"] || "all"
    filter_priority = params["priority"] || "all"
    filter_team = params["team"] || "all"
    active_tab = params["tab"] || "ongoing"

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:filter_status, filter_status)
     |> assign(:filter_priority, filter_priority)
     |> assign(:filter_team, filter_team)
     |> assign(:active_tab, active_tab)
     |> load_requests()}
  end

  defp safe_to_atom(nil, default), do: default
  defp safe_to_atom(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end
  defp safe_to_atom(_, default), do: default

  @impl true
  def handle_event("view_request", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/backlog/#{id}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    request = Requests.get_request!(id)
    {:ok, _} = Requests.delete_request(request)

    {:noreply, load_requests(socket)}
  end

  def handle_event("sort", %{"by" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    sort_order = if socket.assigns.sort_by == field_atom and socket.assigns.sort_order == :asc, do: :desc, else: :asc

    {:noreply,
     push_patch(socket,
       to: ~p"/backlog?#{build_params(socket, sort_by: field, sort_order: Atom.to_string(sort_order))}"
     )}
  end

  def handle_event("apply_filters", %{"status" => status, "priority" => priority, "team" => team}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/backlog?#{build_params(socket, status: status, priority: priority, team: team)}"
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/backlog?sort_by=#{socket.assigns.sort_by}&sort_order=#{socket.assigns.sort_order}&tab=#{socket.assigns.active_tab}"
     )}
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/backlog?#{build_params(socket, tab: tab)}"
     )}
  end

  defp build_params(socket, updates) do
    updates_map = Enum.into(updates, %{}, fn {k, v} -> {Atom.to_string(k), v} end)

    %{
      "sort_by" => Atom.to_string(socket.assigns.sort_by),
      "sort_order" => Atom.to_string(socket.assigns.sort_order),
      "status" => socket.assigns.filter_status,
      "priority" => socket.assigns.filter_priority,
      "team" => socket.assigns.filter_team,
      "tab" => Map.get(updates_map, "tab", socket.assigns.active_tab)
    }
    |> Map.merge(updates_map)
    |> Enum.filter(fn {k, v} -> v != "all" and k != "tab" end)
    |> Enum.into(%{})
    |> Map.put("tab", Map.get(updates_map, "tab", socket.assigns.active_tab))
  end

  defp load_requests(socket) do
    current_user = socket.assigns[:current_user]

    all_requests = Requests.list_requests_by_team(current_user.team_id)
    filtered_requests = apply_filters(all_requests, socket.assigns)

    # Split into three categories
    new_requests = filtered_requests
      |> Enum.filter(&(&1.status == "new"))
      |> apply_sorting(socket.assigns.sort_by, socket.assigns.sort_order)

    ongoing_requests = filtered_requests
      |> Enum.filter(&(&1.status in ["pending", "in_progress", "review", "blocked"]))
      |> apply_sorting(socket.assigns.sort_by, socket.assigns.sort_order)

    completed_requests = filtered_requests
      |> Enum.filter(&(&1.status == "completed"))
      |> apply_sorting(socket.assigns.sort_by, socket.assigns.sort_order)

    socket
    |> assign(:new_requests, new_requests)
    |> assign(:ongoing_requests, ongoing_requests)
    |> assign(:completed_requests, completed_requests)
    |> assign(:total_count, length(filtered_requests))
  end

  defp apply_filters(requests, assigns) do
    requests
    |> filter_by_status(assigns.filter_status)
    |> filter_by_priority(assigns.filter_priority)
    |> filter_by_team(assigns.filter_team)
  end

  defp filter_by_status(requests, "all"), do: requests
  defp filter_by_status(requests, status), do: Enum.filter(requests, &(&1.status == status))

  defp filter_by_priority(requests, "all"), do: requests
  defp filter_by_priority(requests, priority) do
    priority_int = String.to_integer(priority)
    Enum.filter(requests, &(&1.priority == priority_int))
  end

  defp filter_by_team(requests, "all"), do: requests
  defp filter_by_team(requests, team_id) do
    team_int = String.to_integer(team_id)
    Enum.filter(requests, &(&1.requesting_team_id == team_int or &1.assigned_to_team_id == team_int))
  end

  defp apply_sorting(requests, sort_by, sort_order) do
    requests
    |> Enum.sort_by(&Map.get(&1, sort_by), sort_order)
  end

  defp truncate_words(text, word_count) do
    words = String.split(text, ~r/\s+/)

    if length(words) <= word_count do
      text
    else
      words
      |> Enum.take(word_count)
      |> Enum.join(" ")
      |> Kernel.<>("...")
    end
  end
end
