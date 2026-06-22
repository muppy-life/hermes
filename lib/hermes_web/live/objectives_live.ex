defmodule HermesWeb.ObjectivesLive do
  use HermesWeb, :live_view

  alias HermesWeb.ObjectivesLive.Period

  # Statuses counted as "in progress" in the period overview KPI.
  @in_progress_statuses ~w(in_progress review)

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    range = Period.default_range(today)

    {:ok,
     socket
     |> assign(:page_title, gettext("Objectives"))
     |> assign(:today, today)
     |> assign(:range, range)
     |> assign(:picker_open?, false)
     |> assign(:cal_year, today.year)
     |> assign(:cal_quarter, Period.current_quarter(today))
     # Right-pane segmentation: :month or :week grid.
     |> assign(:cal_mode, :month)
     # In-progress month selection: nil | {m1, nil} | {m1, m2} (absolute months).
     |> assign(:sel, nil)
     # In-progress week selection: nil | {key1, nil} | {key1, key2} (Monday ISO).
     |> assign(:week_sel, nil)
     |> set_week_buckets()
     |> load()}
  end

  @impl true
  def handle_event("toggle_picker", _params, socket) do
    opening? = !socket.assigns.picker_open?

    socket =
      socket
      |> assign(:picker_open?, opening?)
      |> assign(:sel, nil)
      |> assign(:week_sel, nil)

    # On open, jump the calendar to the quarter holding most of the range. A
    # range snapped to whole weeks can spill a few days past either quarter
    # edge; the majority quarter ignores that small overlap on both sides.
    socket =
      if opening? do
        {year, quarter} = Period.dominant_quarter(socket.assigns.range)

        socket
        |> assign(:cal_year, year)
        |> assign(:cal_quarter, quarter)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("close_picker", _params, socket) do
    {:noreply,
     socket |> assign(:picker_open?, false) |> assign(:sel, nil) |> assign(:week_sel, nil)}
  end

  def handle_event("set_cal_mode", %{"mode" => mode}, socket) when mode in ~w(month week) do
    mode = String.to_existing_atom(mode)

    # Switching segmentation re-aligns the active range to the new granularity
    # (whole months ↔ whole ISO weeks) and applies it immediately. Any
    # half-finished pick in the other mode is dropped.
    range =
      case mode do
        :week -> Period.to_week_range(socket.assigns.range)
        :month -> Period.to_month_range(socket.assigns.range)
      end

    socket =
      socket
      |> assign(:cal_mode, mode)
      |> assign(:range, range)
      |> assign(:sel, nil)
      |> assign(:week_sel, nil)
      |> set_week_buckets()

    {:noreply, load(socket)}
  end

  def handle_event("select_preset", %{"preset" => preset}, socket) do
    preset = String.to_existing_atom(preset)

    if preset in Period.presets() do
      range = Period.preset_range(preset, socket.assigns.today)
      apply_range(socket, maybe_snap(range, socket))
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_quarter", %{"q" => q}, socket) do
    case Integer.parse(q) do
      {q, ""} when q in 1..4 ->
        range = Period.quarter_range(q, socket.assigns.cal_year)
        apply_range(socket, maybe_snap(range, socket))

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cal_prev_year", _params, socket) do
    {:noreply, assign(socket, :cal_year, socket.assigns.cal_year - 1)}
  end

  def handle_event("cal_next_year", _params, socket) do
    {:noreply, assign(socket, :cal_year, socket.assigns.cal_year + 1)}
  end

  # Quarter steppers wrap Q4→Q1 (and Q1→Q4), rolling the year accordingly.
  def handle_event("cal_prev_quarter", _params, socket) do
    {:noreply, step_quarter(socket, -1)}
  end

  def handle_event("cal_next_quarter", _params, socket) do
    {:noreply, step_quarter(socket, +1)}
  end

  # First click starts a month range; second click closes it and applies.
  def handle_event("pick_month", %{"month" => month}, socket) do
    case Integer.parse(month) do
      {m, ""} when m in 1..12 -> pick_month(socket, m)
      _ -> {:noreply, socket}
    end
  end

  # First click starts a week range; second click closes it and applies. The
  # value is the week's Monday as an ISO date string.
  def handle_event("pick_week", %{"key" => key}, socket) do
    case Date.from_iso8601(key) do
      {:ok, _date} -> pick_week(socket, key)
      _ -> {:noreply, socket}
    end
  end

  # Week drill-down tabs (shown only for a single-month range). Narrows the
  # active range to the chosen week while keeping the week strip in place.
  def handle_event("select_week", %{"key" => key}, socket) do
    case Enum.find(socket.assigns.week_buckets, &(&1.key == key)) do
      nil ->
        {:noreply, socket}

      bucket ->
        socket =
          socket
          |> assign(:range, Map.take(bucket, [:first, :last, :label]))
          |> assign(:active_week_key, key)

        {:noreply, load(socket)}
    end
  end

  # Ignore unrecognised events rather than crashing.
  def handle_event("set_cal_mode", _params, socket), do: {:noreply, socket}
  def handle_event("select_preset", _params, socket), do: {:noreply, socket}
  def handle_event("select_quarter", _params, socket), do: {:noreply, socket}
  def handle_event("pick_month", _params, socket), do: {:noreply, socket}
  def handle_event("pick_week", _params, socket), do: {:noreply, socket}
  def handle_event("select_week", _params, socket), do: {:noreply, socket}

  # In week mode, expand a month/quarter preset range to whole ISO weeks so the
  # left rail segments by week data too. Month mode keeps the exact range.
  defp maybe_snap(range, %{assigns: %{cal_mode: :week}}), do: Period.snap_to_weeks(range)
  defp maybe_snap(range, _socket), do: range

  defp step_quarter(socket, delta) do
    q = socket.assigns.cal_quarter + delta

    {year, quarter} =
      cond do
        q < 1 -> {socket.assigns.cal_year - 1, 4}
        q > 4 -> {socket.assigns.cal_year + 1, 1}
        true -> {socket.assigns.cal_year, q}
      end

    socket
    |> assign(:cal_year, year)
    |> assign(:cal_quarter, quarter)
  end

  defp pick_month(socket, m) do
    case socket.assigns.sel do
      nil ->
        # Start a range; nothing applied yet.
        {:noreply, assign(socket, :sel, {m, nil})}

      {m1, _} ->
        range = Period.month_range(socket.assigns.cal_year, m1, m)
        apply_range(socket, range)
    end
  end

  defp pick_week(socket, key) do
    case socket.assigns.week_sel do
      nil ->
        # Start a week range; nothing applied yet.
        {:noreply, assign(socket, :week_sel, {key, nil})}

      {key1, _} ->
        range = Period.week_range(key1, key)
        apply_range(socket, range)
    end
  end

  # Apply a new active range, rebuild the week drill-down, recompute, and close
  # the picker.
  defp apply_range(socket, range) do
    socket =
      socket
      |> assign(:range, range)
      |> assign(:picker_open?, false)
      |> assign(:sel, nil)
      |> assign(:week_sel, nil)
      |> set_week_buckets()

    {:noreply, load(socket)}
  end

  # Recompute the ISO-week drill-down for the active range (empty unless it is
  # a single calendar month), defaulting the active week to the current one.
  defp set_week_buckets(socket) do
    weeks = Period.week_buckets(socket.assigns.range, socket.assigns.today)

    socket
    |> assign(:week_buckets, weeks)
    |> assign(:active_week_key, Period.current_key(weeks))
  end

  defp load(socket) do
    user = socket.assigns.current_user
    active = socket.assigns.range

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

  # Mean hours from creation to completion, over only the requests with a
  # logged completion transition. Requests without one are excluded entirely
  # (rather than counted as 0) so a partially-logged dataset doesn't deflate
  # the average. Returns nil when no completed request has a logged time.
  defp avg_completion_hours(completed, completed_at) do
    durations =
      completed
      |> Enum.filter(&Map.has_key?(completed_at, &1.id))
      |> Enum.map(fn r ->
        done_at = Map.fetch!(completed_at, r.id)
        # Clamp at 0: back-dated change-log rows can predate the request's own
        # inserted_at, which would otherwise skew the mean negative.
        max(DateTime.diff(to_datetime(done_at), to_datetime(r.inserted_at), :hour), 0)
      end)

    case durations do
      [] -> nil
      _ -> Enum.sum(durations) / length(durations)
    end
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

  @doc "Preset identifiers for the picker rail."
  def presets, do: Period.presets()

  def preset_label(:this_month), do: gettext("This month")
  def preset_label(:last_month), do: gettext("Last month")
  def preset_label(:last_3_months), do: gettext("Last 3 months")
  def preset_label(:last_12_months), do: gettext("Last 12 months")
  def preset_label(:this_year), do: gettext("This year")
  def preset_label(:last_year), do: gettext("Last year")

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
