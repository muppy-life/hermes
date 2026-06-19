defmodule HermesWeb.MetricsLive do
  use HermesWeb, :live_view

  # Statuses shown in the status donut / breakdown (discarded is excluded everywhere).
  @status_order [
    "new",
    "need_requirement",
    "pending",
    "future_planning",
    "todo_in_sprint",
    "in_progress",
    "review",
    "completed",
    "blocked"
  ]

  # Donut segments / legend dots resolve to page-scoped CSS variables so they
  # follow the theme (light/dark) instead of hardcoded hex. Mirrors the muted
  # slate palette from the design.
  @status_var %{
    "new" => "--m-st-new",
    "need_requirement" => "--m-st-need",
    "pending" => "--m-st-pending",
    "future_planning" => "--m-st-future",
    "todo_in_sprint" => "--m-st-todo",
    "in_progress" => "--m-st-progress",
    "review" => "--m-st-review",
    "completed" => "--m-st-done",
    "blocked" => "--m-st-blocked"
  }

  # Time-bucket windows available in the Period chip.
  @periods ~w(weekly monthly quarterly yearly)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Metrics"))
     |> assign(:period, "monthly")
     |> assign(:status_filter, nil)
     |> assign(:priority_filter, nil)
     |> assign(:open_menu, nil)
     |> assign(:hero_slide, 0)
     |> load()}
  end

  @impl true
  def handle_event("toggle_menu", %{"menu" => menu}, socket) do
    open = if socket.assigns.open_menu == menu, do: nil, else: menu
    {:noreply, assign(socket, :open_menu, open)}
  end

  def handle_event("close_menu", _params, socket) do
    {:noreply, assign(socket, :open_menu, nil)}
  end

  def handle_event("set_hero_slide", %{"slide" => slide}, socket) do
    case Integer.parse(slide) do
      {index, ""} when index in 0..1 -> {:noreply, assign(socket, :hero_slide, index)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_period", %{"period" => period}, socket) when period in @periods do
    {:noreply, socket |> assign(:period, period) |> assign(:open_menu, nil) |> load()}
  end

  # Ignore unrecognised period values from the client rather than crashing.
  def handle_event("set_period", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status
    {:noreply, socket |> assign(:status_filter, status) |> assign(:open_menu, nil) |> load()}
  end

  def handle_event("set_priority", %{"priority" => priority}, socket) do
    # priority arrives from the client; parse defensively so a malformed value
    # can't crash the LiveView process.
    priority =
      case Integer.parse(priority) do
        {int, ""} -> int
        _ -> nil
      end

    {:noreply, socket |> assign(:priority_filter, priority) |> assign(:open_menu, nil) |> load()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, nil)
     |> assign(:priority_filter, nil)
     |> assign(:open_menu, nil)
     |> load()}
  end

  def handle_event("export_csv", _params, socket) do
    csv = build_csv(socket.assigns.filtered_requests)

    {:noreply,
     push_event(socket, "download", %{
       filename: "hermes_metrics.csv",
       content: csv,
       mime: "text/csv;charset=utf-8;"
     })}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    requests =
      Hermes.Requests.list_requests_by_team(user.team_id)
      |> Enum.reject(&(&1.status == "discarded"))
      |> apply_filters(socket.assigns.status_filter, socket.assigns.priority_filter)

    today = Date.utc_today()
    total = length(requests)
    completed = Enum.filter(requests, &(&1.status == "completed"))
    done = length(completed)
    in_progress = Enum.count(requests, &(&1.status == "in_progress"))
    blocked = Enum.count(requests, &(&1.status == "blocked"))
    completion_rate = if total > 0, do: round(done / total * 100), else: 0
    avg_cycle = avg_days(completed)

    buckets = period_buckets(socket.assigns.period, today)
    created = bucket_counts(requests, buckets, & &1.inserted_at)
    completed_series = bucket_counts(completed, buckets, & &1.updated_at)

    status_counts =
      Map.new(@status_order, fn s -> {s, Enum.count(requests, &(&1.status == s))} end)

    team_counts =
      requests
      |> count_by_team()
      |> Enum.sort_by(&elem(&1, 1), :desc)

    requester_top =
      requests
      |> Enum.frequencies_by(& &1.created_by)
      |> Enum.reject(fn {u, _} -> is_nil(u) end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(5)

    open = Enum.reject(requests, &(&1.status == "completed"))

    socket
    |> assign(:filtered_requests, requests)
    |> assign(:total, total)
    |> assign(:done, done)
    |> assign(:in_progress, in_progress)
    |> assign(:blocked, blocked)
    |> assign(:completion_rate, completion_rate)
    |> assign(:avg_cycle, avg_cycle)
    |> assign(:buckets, buckets)
    |> assign(:created_series, created)
    |> assign(:completed_series, completed_series)
    |> assign(:status_counts, status_counts)
    |> assign(:team_counts, team_counts)
    |> assign(:requester_top, requester_top)
    |> assign(:aging, aging_buckets(open, today))
    |> assign(:team_time, avg_days_by_team(completed))
    |> assign(:current_index, Enum.find_index(buckets, & &1.current))
  end

  defp apply_filters(requests, status, priority) do
    requests
    |> then(fn rs -> if status, do: Enum.filter(rs, &(&1.status == status)), else: rs end)
    |> then(fn rs -> if priority, do: Enum.filter(rs, &(&1.priority == priority)), else: rs end)
  end

  defp build_csv(requests) do
    header = "id,title,status,priority,team,requester,created_at,updated_at"

    rows =
      Enum.map(requests, fn r ->
        [
          r.id,
          r.title,
          r.status,
          r.priority,
          r.requesting_team && r.requesting_team.name,
          r.created_by && r.created_by.email,
          r.inserted_at,
          r.updated_at
        ]
        |> Enum.map_join(",", &csv_cell/1)
      end)

    Enum.join([header | rows], "\n")
  end

  defp csv_cell(nil), do: ""

  defp csv_cell(value) do
    str = to_string(value)

    # Prefix formula-triggering characters so spreadsheets don't execute a
    # cell like `=HYPERLINK(...)` as a formula (CSV injection).
    safe = if String.starts_with?(str, ["=", "+", "-", "@"]), do: "'" <> str, else: str

    ~s|"#{String.replace(safe, "\"", "\"\"")}"|
  end

  # --- Aggregation helpers ---

  # Average days between inserted_at and updated_at for a set of completed requests.
  defp avg_days([]), do: 0

  defp avg_days(requests) do
    total =
      Enum.reduce(requests, 0, fn r, acc ->
        acc + max(0, DateTime.diff(r.updated_at, r.inserted_at, :day))
      end)

    round(total / length(requests))
  end

  # Time buckets for the selected period, oldest first. Each bucket carries a
  # range [from, to) plus short/full labels and a `current` flag.
  defp period_buckets("weekly", today), do: week_buckets(today, 6)
  defp period_buckets("quarterly", today), do: quarter_buckets(today, 4)
  defp period_buckets("yearly", today), do: year_buckets(today, 4)
  defp period_buckets(_monthly, today), do: month_buckets(today, 5)

  defp month_buckets(today, n) do
    start = Date.beginning_of_month(today) |> Date.shift(month: -(n - 1))

    for offset <- 0..(n - 1) do
      from = Date.shift(start, month: offset)
      to = Date.shift(from, month: 1)

      %{
        from: from,
        to: to,
        short: Calendar.strftime(from, "%b"),
        full: Calendar.strftime(from, "%B %Y"),
        current: today.year == from.year and today.month == from.month
      }
    end
  end

  defp week_buckets(today, n) do
    start = Date.beginning_of_week(today) |> Date.shift(week: -(n - 1))

    for offset <- 0..(n - 1) do
      from = Date.shift(start, week: offset)
      to = Date.shift(from, week: 1)

      %{
        from: from,
        to: to,
        short: "S#{div(from.day - 1, 7) + 1}/#{from.month}",
        full: gettext("Week of %{date}", date: Calendar.strftime(from, "%d %b %Y")),
        current: Date.compare(today, from) != :lt and Date.compare(today, to) == :lt
      }
    end
  end

  defp quarter_buckets(today, n) do
    cur_q = div(today.month - 1, 3)
    start = Date.new!(today.year, cur_q * 3 + 1, 1) |> Date.shift(month: -3 * (n - 1))

    for offset <- 0..(n - 1) do
      from = Date.shift(start, month: 3 * offset)
      to = Date.shift(from, month: 3)
      q = div(from.month - 1, 3) + 1

      %{
        from: from,
        to: to,
        short: "Q#{q}",
        full: "Q#{q} #{from.year}",
        current: Date.compare(today, from) != :lt and Date.compare(today, to) == :lt
      }
    end
  end

  defp year_buckets(today, n) do
    for offset <- 0..(n - 1) do
      year = today.year - (n - 1) + offset
      from = Date.new!(year, 1, 1)

      %{
        from: from,
        to: Date.new!(year + 1, 1, 1),
        short: "#{year}",
        full: "#{year}",
        current: year == today.year
      }
    end
  end

  # Counts per bucket for the given date accessor.
  defp bucket_counts(requests, buckets, date_fun) do
    Enum.map(buckets, fn b ->
      Enum.count(requests, &in_bucket?(date_fun.(&1), b))
    end)
  end

  defp in_bucket?(nil, _bucket), do: false

  defp in_bucket?(dt, %{from: from, to: to}) do
    d = DateTime.to_date(dt)
    Date.compare(d, from) != :lt and Date.compare(d, to) == :lt
  end

  defp count_by_team(requests) do
    requests
    |> Enum.map(& &1.requesting_team)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies_by(& &1.name)
    |> Enum.to_list()
  end

  defp avg_days_by_team(completed) do
    completed
    |> Enum.filter(& &1.requesting_team)
    |> Enum.group_by(& &1.requesting_team.name)
    |> Enum.map(fn {name, reqs} -> {name, avg_days(reqs)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp aging_buckets(open, today) do
    Enum.reduce(open, %{ok: 0, warn: 0, bad: 0}, fn r, acc ->
      days = Date.diff(today, DateTime.to_date(r.inserted_at))

      cond do
        days < 7 -> %{acc | ok: acc.ok + 1}
        days < 30 -> %{acc | warn: acc.warn + 1}
        true -> %{acc | bad: acc.bad + 1}
      end
    end)
  end

  # --- View helpers (exposed to the template) ---

  @doc "Ordered list of statuses shown in distributions."
  def status_order, do: @status_order

  @doc "Available priority filters as {value, label} pairs."
  def priorities do
    [
      {4, gettext("Critical")},
      {3, gettext("Important")},
      {2, gettext("Normal")},
      {1, gettext("Low")}
    ]
  end

  @doc "Period chip options as {value, label} pairs."
  def period_options do
    [
      {"weekly", gettext("Weekly")},
      {"monthly", gettext("Monthly")},
      {"quarterly", gettext("Quarterly")},
      {"yearly", gettext("Yearly")}
    ]
  end

  @doc "Label for the currently selected period."
  def period_label(period) do
    period_options() |> Enum.find_value(gettext("Monthly"), fn {v, l} -> v == period && l end)
  end

  @doc "CSS `var(...)` reference for a status colour, theme-aware."
  def status_color(status) do
    "var(#{Map.get(@status_var, status, "--m-st-pending")})"
  end

  @doc """
  Content for the clickable completion-rate hero. Two slides the user can
  toggle between via the dots: completion rate and average cycle time.
  Returns `%{badge, title, desc}` for the active `slide` index.
  """
  def hero_slide(0, assigns) do
    %{
      badge: gettext("Health"),
      title: gettext("Completion rate · %{rate}%", rate: assigns.completion_rate),
      desc:
        gettext(
          "%{done} completed of %{total} requests. Average resolution time: %{days} days.",
          done: assigns.done,
          total: assigns.total,
          days: assigns.avg_cycle
        )
    }
  end

  def hero_slide(1, assigns) do
    %{
      badge: gettext("Cycle"),
      title: gettext("Average cycle · %{days} days", days: assigns.avg_cycle),
      desc:
        gettext(
          "Average closing time across %{done} completed tasks. %{open} still open in pipeline.",
          done: assigns.done,
          open: assigns.total - assigns.done
        )
    }
  end

  @doc "Percentage of `value` over `total`, rounded, 0 when total is 0."
  def pct(_value, 0), do: 0
  def pct(value, total), do: round(value / total * 100)

  @doc "Initials from an email address."
  def initials(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  def initials(_), do: "?"

  @doc "Display name derived from an email local part."
  def display_name(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.capitalize()
  end

  def display_name(_), do: gettext("Unknown")

  @doc """
  Smooth area SVG (Catmull-Rom-ish) for the KPI mini charts.
  Returns raw SVG markup; render with `raw/1`.
  """
  def mini_area(values, w, h, grad_id, stroke \\ "var(--m-fill)") do
    values = Enum.map(values, &(&1 * 1.0))
    pad = 4.0
    max = Enum.max([1.0 | values])
    cw = w - pad * 2
    ch = h - pad * 2
    n = length(values)
    step = if n > 1, do: cw / (n - 1), else: 0.0

    pts =
      values
      |> Enum.with_index()
      |> Enum.map(fn {v, i} -> {pad + i * step, pad + ch - v / max * ch} end)

    [{x0, y0} | _] = pts
    path = spline_path(pts, "M #{f(x0)} #{f(y0)}")

    {lx, _} = List.last(pts)
    area = path <> " L #{f(lx)} #{f(pad + ch)} L #{f(x0)} #{f(pad + ch)} Z"

    """
    <svg viewBox="0 0 #{w} #{h}" width="100%" height="#{h}" preserveAspectRatio="none" style="display:block">
      <path d="#{area}" fill="url(##{grad_id})"/>
      <path d="#{path}" fill="none" stroke="#{stroke}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    """
  end

  defp spline_path(pts, acc) do
    n = length(pts)
    arr = List.to_tuple(pts)

    Enum.reduce(0..(n - 2)//1, acc, fn i, acc ->
      {p0x, p0y} = elem(arr, max(i - 1, 0))
      {p1x, p1y} = elem(arr, i)
      {p2x, p2y} = elem(arr, i + 1)
      {p3x, p3y} = elem(arr, min(i + 2, n - 1))
      cp1x = p1x + (p2x - p0x) / 5
      cp1y = p1y + (p2y - p0y) / 5
      cp2x = p2x - (p3x - p1x) / 5
      cp2y = p2y - (p3y - p1y) / 5
      acc <> " C #{f(cp1x)} #{f(cp1y)}, #{f(cp2x)} #{f(cp2y)}, #{f(p2x)} #{f(p2y)}"
    end)
  end

  @doc """
  Segmented donut SVG for the status distribution.
  Returns the `<circle>` segments; wrap in an `<svg viewBox="0 0 160 160">`.

  Rendered in two flat z-layers:

    * Bottom — each segment's full body as a flat (butt) arc, so bodies meet
      flush at every seam with no bleed.
    * Top — a small round dot at each segment's trailing (start) edge. A
      zero-length round-capped dash renders as a circle of the stroke's
      diameter; centred on the start boundary, its back half rounds the tip and
      rides over the PREVIOUS segment, while its forward half sits over the
      segment's own body (same colour, invisible).

  Because the rounded part is just a tip dot — not half the segment — there is
  no inner cap to bleed mid-segment, even on tiny slices, and the overlap is
  uniform at every seam including the wrap-around.
  """
  def donut_segments(counts, total) do
    r = 58
    cx = 80
    cy = 80
    stroke = 20
    circ = 2 * :math.pi() * r
    total = max(total, 1)

    placed =
      status_order()
      |> Enum.filter(fn s -> Map.get(counts, s, 0) > 0 end)
      |> Enum.map_reduce(0.0, fn s, offset ->
        len = Map.get(counts, s, 0) / total * circ
        {{s, offset, len}, offset + len}
      end)
      |> elem(0)

    case placed do
      # A single status fills the whole ring — no seam, draw one circle.
      [{s, _offset, _len}] ->
        arc(cx, cy, r, stroke, status_color(s), circ, 0.0, "butt")

      segments ->
        # Bottom layer: flat full-length bodies (flush seams).
        bodies = Enum.map_join(segments, "", &segment_body(&1, cx, cy, r, stroke))

        # Top layer: small rounded tip dots at each segment's START, so each
        # tip rides over the PREVIOUS segment.
        tips = Enum.map_join(segments, "", &segment_tip(&1, cx, cy, r, stroke))

        bodies <> tips
    end
  end

  # Flat (butt) full-length body, bottom layer.
  defp segment_body({s, offset, len}, cx, cy, r, stroke) do
    arc(cx, cy, r, stroke, status_color(s), len, -offset, "butt")
  end

  # Small round dot centred on the trailing (start) edge — the rounded tip that
  # overlaps the previous segment. Near-zero dash length so only the cap shows.
  defp segment_tip({s, offset, _len}, cx, cy, r, stroke) do
    arc(cx, cy, r, stroke, status_color(s), 0.01, -offset, "round")
  end

  # One donut arc as a dashed circle. `dash` is the visible arc length,
  # `dash_offset` its start position (negative = clockwise from 12 o'clock),
  # `cap` the stroke-linecap (round bulges past the arc; butt is flat).
  defp arc(cx, cy, r, stroke, color, dash, dash_offset, cap) do
    circ = 2 * :math.pi() * r

    ~s|<circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="none" stroke="#{color}" stroke-width="#{stroke}" stroke-dasharray="#{f(dash)} #{f(circ)}" stroke-dashoffset="#{f(dash_offset)}" transform="rotate(-90 #{cx} #{cy})" stroke-linecap="#{cap}"/>|
  end

  defp f(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp f(n), do: to_string(n)
end
