defmodule HermesWeb.ObjectivesLive do
  use HermesWeb, :live_view

  @quarters ~w(Q1 Q2 Q3 Q4)

  # Statuses counted as "in progress" in the quarter overview KPI.
  @in_progress_statuses ~w(in_progress review)

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, gettext("Objectives"))
     |> assign(:year, today.year)
     |> assign(:current_quarter, quarter_of_date(today))
     |> assign(:active_quarter, quarter_of_date(today))
     |> load()}
  end

  @impl true
  def handle_event("select_quarter", %{"quarter" => quarter}, socket)
      when quarter in @quarters do
    {:noreply, socket |> assign(:active_quarter, quarter) |> load()}
  end

  # Ignore unrecognised quarter values from the client rather than crashing.
  def handle_event("select_quarter", _params, socket), do: {:noreply, socket}

  defp load(socket) do
    user = socket.assigns.current_user
    year = socket.assigns.year
    active = socket.assigns.active_quarter

    requests =
      Hermes.Requests.list_requests_by_team(user.team_id)
      |> Enum.reject(&(&1.status == "discarded"))

    # Total / in-progress are bucketed by the quarter the request was created in.
    items = Enum.filter(requests, &(quarter_of(&1.inserted_at, year) == active))
    in_progress = Enum.count(items, &(&1.status in @in_progress_statuses))

    # Completed tasks are bucketed by the quarter they were *completed* in,
    # taken from the status change log. Requests without a logged completion
    # transition fall back to their creation date.
    all_completed = Enum.filter(requests, &(&1.status == "completed"))

    completed_at =
      all_completed
      |> Enum.map(& &1.id)
      |> Hermes.Requests.completed_at_by_request()

    completed =
      Enum.filter(all_completed, fn r ->
        date = Map.get(completed_at, r.id) || r.inserted_at
        quarter_of(date, year) == active
      end)

    socket
    |> assign(:items, items)
    |> assign(:total, length(items))
    |> assign(:completed_at, completed_at)
    |> assign(:completed, completed)
    |> assign(:done, length(completed))
    |> assign(:in_progress, in_progress)
    |> assign(:team_counts, completed_by_team(completed))
  end

  # Completion counts per team, sorted descending. Drives the "By team" bars.
  defp completed_by_team(completed) do
    completed
    |> Enum.filter(& &1.requesting_team)
    |> Enum.frequencies_by(& &1.requesting_team.name)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  # Quarter (Q1..Q4) for a datetime, scoped to `year`. Datetimes in another
  # year (or nil) fall outside every quarter bucket.
  defp quarter_of(nil, _year), do: nil

  defp quarter_of(dt, year) do
    date = to_date(dt)
    if date.year == year, do: quarter_of_date(date), else: nil
  end

  # Quarter (Q1..Q4) for a plain Date, ignoring the year.
  defp quarter_of_date(date), do: "Q#{div(date.month - 1, 3) + 1}"

  # Coerce to a Date. Request timestamps are :utc_datetime (DateTime) while
  # RequestChange timestamps are :naive_datetime (NaiveDateTime); both flow
  # through here so neither raises.
  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)

  # --- View helpers ---

  @doc "Ordered list of quarters."
  def quarters, do: @quarters

  @doc """
  Lifecycle state of a quarter relative to the current one:
  `:closed` (past), `:current`, or `:upcoming` (future).
  """
  def quarter_state(quarter, current) do
    cond do
      quarter < current -> :closed
      quarter == current -> :current
      true -> :upcoming
    end
  end

  def quarter_state_label(:closed), do: gettext("closed")
  def quarter_state_label(:current), do: gettext("current")
  def quarter_state_label(:upcoming), do: gettext("upcoming")

  @doc "Percentage of `value` over `total`, rounded, 0 when total is 0."
  def pct(_value, 0), do: 0
  def pct(value, total), do: round(value / total * 100)

  @doc "Display name derived from an email local part."
  def display_name(%{email: email}) when is_binary(email), do: display_name(email)

  def display_name(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.capitalize()
  end

  def display_name(_), do: gettext("Unknown")

  @doc "Short date label for a datetime, e.g. \"14 May 2026\"."
  def short_date(nil), do: ""

  def short_date(dt), do: Calendar.strftime(to_date(dt), "%d %b %Y")
end
