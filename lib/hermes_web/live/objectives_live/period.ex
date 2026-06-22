defmodule HermesWeb.ObjectivesLive.Period do
  @moduledoc """
  Date-range selection for the Objectives page.

  The page is driven by a single **active range** — `%{first, last, label}` with
  inclusive `Date` bounds — produced either by a named preset, a quarter, or a
  custom month range chosen from the picker. `in_range?/2` filters requests
  against it.

  When the active range is exactly one calendar month, `week_buckets/2` yields
  the ISO weeks overlapping it so the page can offer a week drill-down.
  """

  # Presets shown in the picker's left rail, in display order.
  @presets ~w(this_month last_month last_3_months last_12_months this_year last_year)a

  @type range :: %{first: Date.t(), last: Date.t(), label: String.t()}

  @type bucket :: %{
          key: String.t(),
          label: String.t(),
          first: Date.t(),
          last: Date.t(),
          state: :closed | :current | :upcoming
        }

  @doc "Ordered preset identifiers for the picker rail."
  @spec presets() :: [atom]
  def presets, do: @presets

  @doc "The default active range when the page loads (the current quarter)."
  @spec default_range(Date.t()) :: range
  def default_range(today), do: quarter_range(current_quarter(today), today.year)

  @doc "The quarter (1..4) containing `date`."
  @spec current_quarter(Date.t()) :: 1..4
  def current_quarter(date), do: div(date.month - 1, 3) + 1

  @doc """
  The `{year, quarter}` holding the most days of `range`. Ties (and short
  ranges) fall to the earliest quarter. Lets the picker open on the quarter a
  range mostly lives in, ignoring a few spillover days at either edge.
  """
  @spec dominant_quarter(range) :: {integer, 1..4}
  def dominant_quarter(%{first: first, last: last}) do
    Date.range(first, last)
    |> Enum.frequencies_by(&{&1.year, current_quarter(&1)})
    |> Enum.max_by(fn {{year, q}, count} -> {count, -year, -q} end)
    |> elem(0)
  end

  @doc """
  Inclusive date range for a named preset, relative to `today`.

  - `:this_month` / `:last_month` — a single calendar month
  - `:last_3_months` / `:last_12_months` — rolling windows ending this month
  - `:this_year` / `:last_year` — a full calendar year
  """
  @spec preset_range(atom, Date.t()) :: range
  def preset_range(:this_month, today) do
    first = first_of_month(today)
    %{first: first, last: Date.end_of_month(first), label: preset_label(:this_month)}
  end

  def preset_range(:last_month, today) do
    first = add_months(first_of_month(today), -1)
    %{first: first, last: Date.end_of_month(first), label: preset_label(:last_month)}
  end

  def preset_range(:last_3_months, today) do
    first = add_months(first_of_month(today), -2)
    %{first: first, last: Date.end_of_month(today), label: preset_label(:last_3_months)}
  end

  def preset_range(:last_12_months, today) do
    first = add_months(first_of_month(today), -11)
    %{first: first, last: Date.end_of_month(today), label: preset_label(:last_12_months)}
  end

  def preset_range(:this_year, today) do
    %{
      first: Date.new!(today.year, 1, 1),
      last: Date.new!(today.year, 12, 31),
      label: preset_label(:this_year)
    }
  end

  def preset_range(:last_year, today) do
    %{
      first: Date.new!(today.year - 1, 1, 1),
      last: Date.new!(today.year - 1, 12, 31),
      label: preset_label(:last_year)
    }
  end

  @doc "Inclusive range for quarter `q` (1..4) of `year`."
  @spec quarter_range(1..4, integer) :: range
  def quarter_range(q, year) when q in 1..4 do
    %{
      first: Date.new!(year, (q - 1) * 3 + 1, 1),
      last: Date.end_of_month(Date.new!(year, q * 3, 1)),
      label: "Q#{q} #{year}"
    }
  end

  @doc """
  Custom month range within `year`, spanning months `m1`..`m2` inclusive
  (order-independent). A single month yields e.g. `"May 2026"`, a span
  `"Mar – Jun 2026"`.
  """
  @spec month_range(integer, 1..12, 1..12) :: range
  def month_range(year, m1, m2) do
    {lo, hi} = {min(m1, m2), max(m1, m2)}
    first = Date.new!(year, lo, 1)
    last = Date.end_of_month(Date.new!(year, hi, 1))

    label =
      if lo == hi do
        Calendar.strftime(first, "%b %Y")
      else
        "#{Calendar.strftime(first, "%b")} – #{Calendar.strftime(last, "%b %Y")}"
      end

    %{first: first, last: last, label: label}
  end

  @doc """
  Expand `range` to whole ISO weeks: `first` moves back to the Monday of its
  week and `last` forward to the Sunday of its week. The label is preserved.
  Used so month/quarter presets cover full weeks while in week mode.
  """
  @spec snap_to_weeks(range) :: range
  def snap_to_weeks(%{first: first, last: last} = range) do
    %{range | first: beginning_of_week(first), last: Date.add(beginning_of_week(last), 6)}
  end

  @doc """
  Convert `range` to a whole-week range, relabelled to read as weeks (e.g.
  `"W14 – W27 2026"`). Used when switching the picker to week segmentation.
  """
  @spec to_week_range(range) :: range
  def to_week_range(range) do
    %{first: first, last: last} = snap_to_weeks(range)
    week_range(Date.to_iso8601(first), Date.to_iso8601(Date.add(last, -6)))
  end

  @doc """
  Convert `range` to a whole-month range covering the months it *mostly* spans,
  relabelled to read as months (e.g. `"Apr – Jun 2026"`). A month is included
  only when the range covers the majority of its days, so the few edge days a
  week-aligned range borrows from the adjacent months don't widen the result.
  Falls back to every touched month if none reach a majority.
  """
  @spec to_month_range(range) :: range
  def to_month_range(%{first: first, last: last} = range) do
    months =
      Date.range(first, last)
      |> Enum.frequencies_by(&{&1.year, &1.month})
      |> Enum.filter(fn {{y, m}, days} -> days * 2 > Date.days_in_month(Date.new!(y, m, 1)) end)
      |> Enum.map(&elem(&1, 0))

    case months do
      [] -> to_month_range_touching(range)
      _ -> month_span_range(Enum.min(months), Enum.max(months))
    end
  end

  # Every month the range touches (used when no single month has a majority).
  defp to_month_range_touching(%{first: first, last: last}) do
    month_span_range({first.year, first.month}, {last.year, last.month})
  end

  defp month_span_range({y1, m1}, {y2, m2}) do
    m_first = Date.new!(y1, m1, 1)
    m_last = Date.end_of_month(Date.new!(y2, m2, 1))

    label =
      if y1 == y2 do
        month_range(y1, m1, m2).label
      else
        "#{month_year(m_first)} – #{month_year(m_last)}"
      end

    %{first: m_first, last: m_last, label: label}
  end

  defp month_year(date), do: Calendar.strftime(date, "%b %Y")

  @doc """
  The 12 month cells of `year` for the full-year 4×3 grid. Each cell carries the
  month number (1..12), short label, and whether it falls inside the in-progress
  selection `sel` (a `{m1, m2 | nil}` month tuple, or nil).
  """
  @spec month_grid(integer, {1..12, 1..12 | nil} | nil) :: [map]
  def month_grid(year, sel) do
    for m <- 1..12 do
      date = Date.new!(year, m, 1)

      %{
        month: m,
        label: Calendar.strftime(date, "%b"),
        selected: month_selected?(m, sel)
      }
    end
  end

  defp month_selected?(_m, nil), do: false
  defp month_selected?(m, {m1, nil}), do: m == m1

  defp month_selected?(m, {m1, m2}) do
    {lo, hi} = {min(m1, m2), max(m1, m2)}
    m >= lo and m <= hi
  end

  @doc "Whether `range` covers exactly one calendar month (enables week drill-down)."
  @spec single_month?(range) :: boolean
  def single_month?(%{first: first, last: last}) do
    first.day == 1 and last == Date.end_of_month(first) and
      first.year == last.year and first.month == last.month
  end

  @doc """
  The active range projected onto `year`'s months as `{m1, m2}` for grid
  highlighting, or nil when the range doesn't overlap `year`. Ranges that span
  into other years are clamped to Jan/Dec of `year`.
  """
  @spec range_months_in_year(range | nil, integer) :: {1..12, 1..12} | nil
  def range_months_in_year(nil, _year), do: nil

  def range_months_in_year(%{first: first, last: last}, year) do
    if first.year > year or last.year < year do
      nil
    else
      {if(first.year == year, do: first.month, else: 1),
       if(last.year == year, do: last.month, else: 12)}
    end
  end

  defp preset_label(:this_month), do: "This month"
  defp preset_label(:last_month), do: "Last month"
  defp preset_label(:last_3_months), do: "Last 3 months"
  defp preset_label(:last_12_months), do: "Last 12 months"
  defp preset_label(:this_year), do: "This year"
  defp preset_label(:last_year), do: "Last year"

  @doc """
  Whether `datetime` falls within the inclusive range's bounds. Accepts
  Date/DateTime/NaiveDateTime; nil and a nil range are never in range.
  """
  @spec in_range?(Date.t() | DateTime.t() | NaiveDateTime.t() | nil, range | nil) :: boolean
  def in_range?(nil, _range), do: false
  def in_range?(_dt, nil), do: false

  def in_range?(dt, %{first: first, last: last}) do
    date = to_date(dt)
    Date.compare(date, first) != :lt and Date.compare(date, last) != :gt
  end

  # --- Weeks (drill-down for a single-month range) ---

  @doc """
  ISO week buckets overlapping `range`, valid only when the range is a single
  calendar month (see `single_month?/1`). Returns `[]` otherwise.
  """
  @spec week_buckets(range, Date.t()) :: [bucket]
  def week_buckets(range, today) do
    if single_month?(range), do: week_buckets_for_month(range.first, today), else: []
  end

  @doc "Key of the bucket containing today, else the first bucket (or nil)."
  @spec current_key([bucket]) :: String.t() | nil
  def current_key(buckets) do
    case Enum.find(buckets, &(&1.state == :current)) do
      nil -> buckets |> List.first() |> then(&(&1 && &1.key))
      bucket -> bucket.key
    end
  end

  # --- Quarter-scoped week grid (picker centre, week mode) ---

  @doc """
  ISO week cells (Mon-start) overlapping quarter `q` of `year`, for the picker's
  4×3 week grid. Each cell is keyed by its Monday's ISO date string and carries
  the ISO week number, inclusive `first`/`last`, a short range label, and whether
  its Monday falls inside the in-progress selection `sel` — a `{key1, key2 | nil}`
  tuple of Monday ISO strings, or nil.
  """
  @spec quarter_week_cells(integer, 1..4, {String.t(), String.t() | nil} | nil) :: [map]
  def quarter_week_cells(year, q, sel) do
    q_first = Date.new!(year, (q - 1) * 3 + 1, 1)
    q_last = Date.end_of_month(Date.new!(year, q * 3, 1))
    first_week = beginning_of_week(q_first)
    count = Integer.floor_div(Date.diff(q_last, first_week), 7) + 1

    for offset <- 0..(count - 1) do
      first = Date.add(first_week, offset * 7)
      last = Date.add(first, 6)
      key = Date.to_iso8601(first)
      {_y, week} = :calendar.iso_week_number({first.year, first.month, first.day})

      %{
        key: key,
        week: week,
        first: first,
        last: last,
        label: "W#{week}",
        sublabel: week_range_label(first, last),
        selected: week_key_selected?(first, sel)
      }
    end
  end

  defp week_key_selected?(_monday, nil), do: false
  defp week_key_selected?(monday, {k1, nil}), do: Date.to_iso8601(monday) == k1

  defp week_key_selected?(monday, {k1, k2}) do
    {lo, hi} = sorted_dates(k1, k2)
    Date.compare(monday, lo) != :lt and Date.compare(monday, hi) != :gt
  end

  defp sorted_dates(k1, k2) do
    d1 = Date.from_iso8601!(k1)
    d2 = Date.from_iso8601!(k2)
    if Date.compare(d1, d2) == :gt, do: {d2, d1}, else: {d1, d2}
  end

  @doc """
  The active range projected onto a `{first_monday_key, last_monday_key}` pair
  for week-grid highlighting, or nil when the range isn't week-aligned. Lets a
  committed week range light up when the picker reopens.
  """
  @spec range_week_keys(range | nil) :: {String.t(), String.t()} | nil
  def range_week_keys(nil), do: nil

  def range_week_keys(%{first: first, last: last}) do
    if Date.day_of_week(first) == 1 and Date.day_of_week(last) == 7 do
      # `last` is a Sunday; its week's key is the Monday six days earlier.
      {Date.to_iso8601(first), Date.to_iso8601(Date.add(last, -6))}
    else
      nil
    end
  end

  @doc """
  Active range spanning the weeks whose Mondays are `key1`..`key2` (inclusive,
  order-independent ISO date strings): the first Monday to the last Sunday.
  """
  @spec week_range(String.t(), String.t()) :: range
  def week_range(key1, key2) do
    {lo, hi} = sorted_dates(key1, key2)
    last = Date.add(hi, 6)
    {_y1, w1} = :calendar.iso_week_number({lo.year, lo.month, lo.day})
    {_y2, w2} = :calendar.iso_week_number({hi.year, hi.month, hi.day})

    label =
      if lo == hi do
        "W#{w1} #{lo.year}"
      else
        "W#{w1} – W#{w2} #{hi.year}"
      end

    %{first: lo, last: last, label: label}
  end

  defp first_of_month(date), do: %{date | day: 1}

  defp add_months(date, 0), do: date

  defp add_months(date, n) when n > 0 do
    months = date.month - 1 + n
    Date.new!(date.year + div(months, 12), rem(months, 12) + 1, 1)
  end

  defp add_months(date, n) when n < 0 do
    months = date.month - 1 + n
    years = Integer.floor_div(months, 12)
    Date.new!(date.year + years, Integer.mod(months, 12) + 1, 1)
  end

  # --- Week ---

  # ISO weeks (Mon-start) that overlap the calendar month of `month_first`.
  # State is relative to the week containing `today`. Each week is shown whole,
  # even where it spills past the month's edges.
  defp week_buckets_for_month(month_first, today) do
    month_last = Date.end_of_month(month_first)
    current_week = beginning_of_week(today)

    first_week = beginning_of_week(month_first)
    week_count = Integer.floor_div(Date.diff(month_last, first_week), 7) + 1

    for offset <- 0..(week_count - 1) do
      first = Date.add(first_week, offset * 7)
      last = Date.add(first, 6)
      {year, week} = :calendar.iso_week_number({first.year, first.month, first.day})

      %{
        key: "week:#{year}:#{week}",
        label: "W#{week} · #{week_range_label(first, last)}",
        first: first,
        last: last,
        state: date_state(first, current_week)
      }
    end
  end

  # "15–21 Jun" or, across a month edge, "29 Jun – 5 Jul".
  defp week_range_label(first, last) do
    if first.month == last.month do
      "#{first.day}–#{last.day} #{month_abbr(last)}"
    else
      "#{first.day} #{month_abbr(first)} – #{last.day} #{month_abbr(last)}"
    end
  end

  defp month_abbr(date), do: Calendar.strftime(date, "%b")

  # ISO week: Monday-start.
  defp beginning_of_week(date), do: Date.add(date, -(Date.day_of_week(date) - 1))

  # --- Shared ---

  defp date_state(first, current) do
    case Date.compare(first, current) do
      :lt -> :closed
      :eq -> :current
      :gt -> :upcoming
    end
  end

  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
end
