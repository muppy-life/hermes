defmodule HermesWeb.ObjectivesLive.Period do
  @moduledoc """
  Time-frame buckets for the Objectives page.

  A *bucket* is one selectable slot of a granularity (one quarter, month or
  week) with an inclusive date range and a lifecycle `state` relative to today
  (`:closed` past, `:current`, `:upcoming` future). The active bucket's range
  is what requests are filtered against — see `in_range?/2`.

  Quarters cover Q1..Q4 of the current year. Months use a rolling window
  centred on today. Weeks are scoped to a selected month: the ISO weeks
  overlapping that month, with the month itself picked from the same rolling
  month window.
  """

  # Rolling window for the month dropdown: how many months to show before and
  # after the current one (also drives the week-mode month picker).
  @months_back 3
  @months_fwd 3

  @type bucket :: %{
          key: String.t(),
          label: String.t(),
          first: Date.t(),
          last: Date.t(),
          state: :closed | :current | :upcoming
        }

  @doc """
  Ordered buckets for `period`, relative to `today`.

  Week buckets are scoped to a month: pass the selected month key (e.g.
  `"month:2026:6"`), and the ISO weeks overlapping that month are returned.
  With no month key the week buckets cover the month containing `today`.
  """
  @spec buckets(:quarter | :month | :week, Date.t(), String.t() | nil) :: [bucket]
  def buckets(period, today, month_key \\ nil)
  def buckets(:quarter, today, _month_key), do: quarter_buckets(today)
  def buckets(:month, today, _month_key), do: month_buckets(today)
  def buckets(:week, today, month_key), do: week_buckets_for_month(month_key, today)

  @doc "Month dropdown options (the month buckets), used by month and week modes."
  @spec month_options(Date.t()) :: [bucket]
  def month_options(today), do: month_buckets(today)

  @doc "Key of the month bucket containing today."
  @spec current_month_key(Date.t()) :: String.t()
  def current_month_key(today), do: "month:#{today.year}:#{today.month}"

  @doc "Key of the bucket containing today, falling back to the last bucket."
  @spec current_key([bucket]) :: String.t() | nil
  def current_key(buckets) do
    case Enum.find(buckets, &(&1.state == :current)) do
      nil -> buckets |> List.last() |> then(&(&1 && &1.key))
      bucket -> bucket.key
    end
  end

  @doc """
  Whether `datetime` falls within the active bucket's inclusive date range.
  Accepts Date/DateTime/NaiveDateTime; nil and a nil bucket are never in range.
  """
  @spec in_range?(Date.t() | DateTime.t() | NaiveDateTime.t() | nil, bucket | nil) :: boolean
  def in_range?(nil, _bucket), do: false
  def in_range?(_dt, nil), do: false

  def in_range?(dt, %{first: first, last: last}) do
    date = to_date(dt)
    Date.compare(date, first) != :lt and Date.compare(date, last) != :gt
  end

  # --- Quarter ---

  defp quarter_buckets(today) do
    current = quarter_index(today)

    for q <- 1..4 do
      first = Date.new!(today.year, (q - 1) * 3 + 1, 1)
      last = Date.end_of_month(Date.new!(today.year, q * 3, 1))

      %{
        key: "quarter:#{today.year}:Q#{q}",
        label: "Q#{q}",
        first: first,
        last: last,
        state: state_for(q, current)
      }
    end
  end

  defp quarter_index(date), do: div(date.month - 1, 3) + 1

  # --- Month ---

  defp month_buckets(today) do
    start = first_of_month(today) |> add_months(-@months_back)
    current = first_of_month(today)

    for offset <- 0..(@months_back + @months_fwd) do
      first = add_months(start, offset)
      last = Date.end_of_month(first)

      %{
        key: "month:#{first.year}:#{first.month}",
        label: Calendar.strftime(first, "%b %Y"),
        first: first,
        last: last,
        state: date_state(first, current)
      }
    end
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

  # ISO weeks (Mon-start) that overlap the month named by `month_key`. State is
  # relative to the week containing `today`. Each week is shown whole, even
  # where it spills past the month's edges.
  defp week_buckets_for_month(month_key, today) do
    month_first = month_first_from_key(month_key, today)
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

  # Resolve a "month:YYYY:M" key to its first-of-month date, falling back to the
  # month containing `today` for nil/garbage.
  defp month_first_from_key("month:" <> rest, today) do
    case String.split(rest, ":") do
      [y, m] ->
        with {year, ""} <- Integer.parse(y),
             {month, ""} <- Integer.parse(m),
             {:ok, date} <- Date.new(year, month, 1) do
          date
        else
          _ -> first_of_month(today)
        end

      _ ->
        first_of_month(today)
    end
  end

  defp month_first_from_key(_key, today), do: first_of_month(today)

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

  defp state_for(value, current) do
    cond do
      value < current -> :closed
      value == current -> :current
      true -> :upcoming
    end
  end

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
