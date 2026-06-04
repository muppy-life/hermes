defmodule HermesWeb.RequestLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias Hermes.Requests

  @doc "Sortable table header cell for the backlog table."
  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :sort_by, :atom, required: true
  attr :sort_order, :atom, required: true
  attr :width, :string, default: nil

  def th(assigns) do
    ~H"""
    <th
      style={@width && "width: #{@width}"}
      phx-click="sort"
      phx-value-by={@field}
      class="px-[22px] py-3.5 text-left text-[10.5px] font-semibold uppercase tracking-[0.08em] text-base-content/50 hover:text-base-content/70 border-b border-base-300 whitespace-nowrap cursor-pointer select-none"
    >
      {@label}<span :if={to_string(@sort_by) == @field} class="ml-1">{if @sort_order == :asc, do: "↑", else: "↓"}</span>
    </th>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Team Requests")
     |> assign(:teams, Accounts.list_teams())
     |> assign(:show_new_request, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    sort_by = safe_to_atom(params["sort_by"], :inserted_at)
    sort_order = safe_to_atom(params["sort_order"], :desc)
    filter_status = params["status"] || "all"
    filter_priority = params["priority"] || "all"
    filter_team = params["team"] || "all"
    filter_search = params["search"] || ""

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:filter_status, filter_status)
     |> assign(:filter_priority, filter_priority)
     |> assign(:filter_team, filter_team)
     |> assign(:filter_search, filter_search)
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

  def handle_event("show_new_request", _params, socket) do
    {:noreply, assign(socket, :show_new_request, true)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    request = Requests.get_request!(id)
    {:ok, _} = Requests.delete_request(request)

    {:noreply, load_requests(socket)}
  end

  def handle_event("sort", %{"by" => field}, socket) do
    field_atom = String.to_existing_atom(field)

    sort_order =
      if socket.assigns.sort_by == field_atom and socket.assigns.sort_order == :asc,
        do: :desc,
        else: :asc

    {:noreply,
     push_patch(socket,
       to:
         ~p"/backlog?#{build_params(socket, sort_by: field, sort_order: Atom.to_string(sort_order))}"
     )}
  end

  def handle_event(
        "apply_filters",
        %{"status" => status, "priority" => priority, "team" => team} = params,
        socket
      ) do
    search = Map.get(params, "search", socket.assigns.filter_search)

    {:noreply,
     push_patch(socket,
       to:
         ~p"/backlog?#{build_params(socket, status: status, priority: priority, team: team, search: search)}"
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/backlog?sort_by=#{socket.assigns.sort_by}&sort_order=#{socket.assigns.sort_order}"
     )}
  end

  @impl true
  def handle_info(:hide_new_request, socket) do
    {:noreply, assign(socket, :show_new_request, false)}
  end

  def handle_info({:new_request_created, _request}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Request created successfully"))
     |> load_requests()}
  end

  def handle_info({:new_request_flash, kind, msg}, socket) do
    {:noreply, put_flash(socket, kind, msg)}
  end

  defp build_params(socket, updates) do
    updates_map = Enum.into(updates, %{}, fn {k, v} -> {Atom.to_string(k), v} end)

    %{
      "sort_by" => Atom.to_string(socket.assigns.sort_by),
      "sort_order" => Atom.to_string(socket.assigns.sort_order),
      "status" => socket.assigns.filter_status,
      "priority" => socket.assigns.filter_priority,
      "team" => socket.assigns.filter_team,
      "search" => socket.assigns.filter_search
    }
    |> Map.merge(updates_map)
    |> Enum.reject(fn {_k, v} -> v in ["all", ""] end)
    |> Enum.into(%{})
  end

  defp load_requests(socket) do
    current_user = socket.assigns[:current_user]

    requests =
      Requests.list_requests_by_team(current_user.team_id)
      |> apply_filters(socket.assigns)
      |> apply_sorting(socket.assigns.sort_by, socket.assigns.sort_order)

    socket
    |> assign(:requests, requests)
    |> assign(:total_count, length(requests))
  end

  defp apply_filters(requests, assigns) do
    requests
    |> filter_by_status(assigns.filter_status)
    |> filter_by_priority(assigns.filter_priority)
    |> filter_by_team(assigns.filter_team)
    |> filter_by_search(assigns.filter_search)
  end

  defp filter_by_search(requests, ""), do: requests

  defp filter_by_search(requests, search) do
    q = String.downcase(search)

    Enum.filter(requests, fn r ->
      String.contains?(String.downcase(r.title || ""), q) or
        String.contains?(String.downcase(r.description || ""), q) or
        String.contains?("##{r.id}", q)
    end)
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

    Enum.filter(
      requests,
      &(&1.requesting_team_id == team_int or &1.assigned_to_team_id == team_int)
    )
  end

  defp apply_sorting(requests, sort_by, sort_order) do
    requests
    |> Enum.sort_by(&Map.get(&1, sort_by), sort_order)
  end

  @doc "Days since the request was created."
  def aging_days(%{inserted_at: nil}), do: 0

  def aging_days(%{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(), to_datetime(inserted_at), :day)
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  @doc "Tailwind text color class for an aging value (green <7d, amber <30d, red otherwise)."
  def aging_class(days) when days < 7, do: "text-success"
  def aging_class(days) when days < 30, do: "text-warning"
  def aging_class(_days), do: "text-error"
end
