defmodule HermesWeb.ObjectivesLive do
  use HermesWeb, :live_view

  alias HermesWeb.ObjectivesLive.Period

  @periods ~w(quarter month week)a

  # Statuses counted as "in progress" in the period overview KPI.
  @in_progress_statuses ~w(in_progress review)

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    period = :quarter
    week_month_key = Period.current_month_key(today)
    buckets = Period.buckets(period, today, week_month_key)

    {:ok,
     socket
     |> assign(:page_title, gettext("Objectives"))
     |> assign(:today, today)
     |> assign(:period, period)
     |> assign(:week_month_key, week_month_key)
     |> assign(:month_options, Period.month_options(today))
     |> assign(:buckets, buckets)
     |> assign(:active_key, Period.current_key(buckets))
     |> load()}
  end

  @impl true
  def handle_event("select_period", %{"period" => period}, socket)
      when period in ~w(quarter month week) do
    period = String.to_existing_atom(period)
    buckets = Period.buckets(period, socket.assigns.today, socket.assigns.week_month_key)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:buckets, buckets)
     |> assign(:active_key, Period.current_key(buckets))
     |> load()}
  end

  # Week mode: pick the month whose ISO weeks are listed.
  def handle_event("select_week_month", %{"key" => key}, socket) do
    if Enum.any?(socket.assigns.month_options, &(&1.key == key)) do
      buckets = Period.buckets(:week, socket.assigns.today, key)

      {:noreply,
       socket
       |> assign(:week_month_key, key)
       |> assign(:buckets, buckets)
       |> assign(:active_key, Period.default_week_key(buckets))
       |> load()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_bucket", %{"key" => key}, socket) do
    if Enum.any?(socket.assigns.buckets, &(&1.key == key)) do
      {:noreply, socket |> assign(:active_key, key) |> load()}
    else
      # Ignore unrecognised bucket keys from the client rather than crashing.
      {:noreply, socket}
    end
  end

  # Ignore unrecognised events rather than crashing.
  def handle_event("select_period", _params, socket), do: {:noreply, socket}
  def handle_event("select_week_month", _params, socket), do: {:noreply, socket}
  def handle_event("select_bucket", _params, socket), do: {:noreply, socket}

  defp load(socket) do
    user = socket.assigns.current_user
    active = Enum.find(socket.assigns.buckets, &(&1.key == socket.assigns.active_key))

    requests =
      Hermes.Requests.list_requests_by_team(user.team_id)
      |> Enum.reject(&(&1.status == "discarded"))

    # Total / in-progress are bucketed by the period the request was created in.
    items = Enum.filter(requests, &Period.in_range?(&1.inserted_at, active))
    in_progress = Enum.count(items, &(&1.status in @in_progress_statuses))

    # Completed tasks are bucketed by the period they were *completed* in,
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
        Period.in_range?(date, active)
      end)

    socket
    |> assign(:active, active)
    |> assign(:items, items)
    |> assign(:total, length(items))
    |> assign(:completed_at, completed_at)
    |> assign(:completed, completed)
    |> assign(:done, length(completed))
    |> assign(:in_progress, in_progress)
    |> assign(:team_counts, completed_by_team(completed))
    |> assign(:avg_completion_hours, avg_completion_hours(completed, completed_at))
  end

  # Mean hours from creation to completion across the completed tasks, or nil
  # when there are none. Completion time comes from the status change log,
  # falling back to creation time (yielding 0 for those requests).
  defp avg_completion_hours([], _completed_at), do: nil

  defp avg_completion_hours(completed, completed_at) do
    durations =
      Enum.map(completed, fn r ->
        done_at = Map.get(completed_at, r.id) || r.inserted_at
        # Clamp at 0: seeded/back-dated change-log rows can predate the
        # request's own inserted_at, which would otherwise skew the mean
        # negative.
        max(DateTime.diff(to_datetime(done_at), to_datetime(r.inserted_at), :hour), 0)
      end)

    Enum.sum(durations) / length(durations)
  end

  # Completion counts per team, sorted descending. Drives the "By team" bars.
  defp completed_by_team(completed) do
    completed
    |> Enum.filter(& &1.requesting_team)
    |> Enum.frequencies_by(& &1.requesting_team.name)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  # Coerce to a Date. Request timestamps are :utc_datetime (DateTime) while
  # RequestChange timestamps are :naive_datetime (NaiveDateTime); both flow
  # through here so neither raises.
  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)

  # Coerce to a UTC DateTime so creation (:utc_datetime) and completion
  # (:naive_datetime, assumed UTC) timestamps can be diffed.
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  # --- View helpers ---

  @doc "Selectable period granularities."
  def periods, do: @periods

  def period_label(:quarter), do: gettext("Quarter")
  def period_label(:month), do: gettext("Month")
  def period_label(:week), do: gettext("Week")

  def bucket_state_label(:closed), do: gettext("closed")
  def bucket_state_label(:current), do: gettext("current")
  def bucket_state_label(:upcoming), do: gettext("upcoming")

  @doc "Percentage of `value` over `total`, rounded, 0 when total is 0."
  def pct(_value, 0), do: 0
  def pct(value, total), do: round(value / total * 100)

  @doc """
  Human label for an average completion duration given in hours, expressed in
  days to one decimal, e.g. `"3.2d"`. Returns an em dash when there is no data.
  """
  def avg_completion_label(nil), do: "—"

  def avg_completion_label(hours) do
    gettext("%{n}d", n: :erlang.float_to_binary(hours / 24, decimals: 1))
  end

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
