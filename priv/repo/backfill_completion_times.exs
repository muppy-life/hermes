# Backfills realistic completion durations for existing completed requests.
#
# Seed data inserts requests with status "completed" but no status-change log,
# so creation == completion and the "Avg. completion time" KPI reads 0. This
# script backdates each completed request's inserted_at and logs a "completed"
# RequestChange a realistic span later, yielding non-zero durations to view.
#
# Run: mix run priv/repo/backfill_completion_times.exs

import Ecto.Query

alias Hermes.Repo
alias Hermes.Requests.{Request, RequestChange}

now = DateTime.utc_now() |> DateTime.truncate(:second)

# Spread completions across the current quarter so they show up under the
# active-quarter view. Vary the create->complete span per request.
completed = Repo.all(from(r in Request, where: r.status == "completed"))

# Hours from creation to completion, cycled across the requests.
spans_hours = [6, 20, 48, 72, 120, 9, 30, 96, 14, 60]

# Pick a creator/user for the change-log row (any user; nil is allowed).
user_id =
  case Repo.all(from(u in Hermes.Accounts.User, select: u.id, limit: 1)) do
    [id | _] -> id
    [] -> nil
  end

{count, _} =
  completed
  |> Enum.with_index()
  |> Enum.reduce({0, []}, fn {req, idx}, {n, _} ->
    span = Enum.at(spans_hours, rem(idx, length(spans_hours)))

    # Completion at a recent point, creation `span` hours before it.
    completed_at = DateTime.add(now, -(idx * 36), :hour)
    created_at = DateTime.add(completed_at, -span, :hour)

    created_naive = DateTime.to_naive(created_at) |> NaiveDateTime.truncate(:second)
    completed_naive = DateTime.to_naive(completed_at) |> NaiveDateTime.truncate(:second)

    # Backdate the request's creation.
    Repo.update_all(
      from(r in Request, where: r.id == ^req.id),
      set: [inserted_at: created_at]
    )

    # Remove any prior logged completion to keep this idempotent.
    Repo.delete_all(
      from(rc in RequestChange,
        where: rc.request_id == ^req.id and rc.field == "status" and rc.new_value == "completed"
      )
    )

    # Log the completion transition at created_at + span.
    Repo.insert!(%RequestChange{
      request_id: req.id,
      user_id: user_id,
      action: "update",
      field: "status",
      old_value: "in_progress",
      new_value: "completed",
      inserted_at: completed_naive
    })

    {n + 1, [created_naive, completed_naive]}
  end)

IO.puts("✅ Backfilled completion times for #{count} completed requests.")
