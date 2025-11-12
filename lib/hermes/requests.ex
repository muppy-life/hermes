defmodule Hermes.Requests do
  @moduledoc """
  The Requests context for managing team requests.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo
  alias Hermes.Requests.Request
  alias Hermes.Requests.RequestChange
  alias Hermes.Requests.RequestComment

  def list_requests do
    Request
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def list_requests_by_team(team_id) do
    from(r in Request,
      where: r.requesting_team_id == ^team_id or r.assigned_to_team_id == ^team_id,
      order_by: [desc: r.updated_at]
    )
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def list_pending_requests do
    from(r in Request, where: r.status == "pending", order_by: [desc: r.priority, desc: r.inserted_at])
    |> Repo.all()
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def get_request!(id) do
    Repo.get!(Request, id)
    |> Repo.preload([:requesting_team, :assigned_to_team, :created_by])
  end

  def create_request(attrs \\ %{}, user_id \\ nil) do
    result =
      %Request{}
      |> Request.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, request} ->
        log_change(request.id, user_id, "created", %{changes: attrs})
        {:ok, request}

      error ->
        error
    end
  end

  def update_request(%Request{} = request, attrs, user_id \\ nil) do
    changeset = Request.changeset(request, attrs)
    changes = changeset.changes

    result = Repo.update(changeset)

    case result do
      {:ok, updated_request} ->
        if map_size(changes) > 0 do
          log_changes(updated_request.id, user_id, request, changes)
        end

        {:ok, updated_request}

      error ->
        error
    end
  end

  def delete_request(%Request{} = request) do
    Repo.delete(request)
  end

  def change_request(%Request{} = request, attrs \\ %{}) do
    Request.changeset(request, attrs)
  end

  # Request change tracking functions

  def list_request_changes(request_id) do
    from(rc in RequestChange,
      where: rc.request_id == ^request_id,
      order_by: [desc: rc.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp log_change(request_id, user_id, action, attrs \\ %{}) do
    %RequestChange{}
    |> RequestChange.changeset(
      Map.merge(attrs, %{
        request_id: request_id,
        user_id: user_id,
        action: action
      })
    )
    |> Repo.insert()
  end

  defp log_changes(request_id, user_id, old_request, changes) do
    # Log each field change individually
    Enum.each(changes, fn {field, new_value} ->
      old_value = Map.get(old_request, field)

      log_change(request_id, user_id, "updated", %{
        field: to_string(field),
        old_value: format_value(old_value),
        new_value: format_value(new_value)
      })
    end)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_nil(value), do: nil
  defp format_value(value), do: inspect(value)

  # Request comment functions

  def list_request_comments(request_id) do
    from(rc in RequestComment,
      where: rc.request_id == ^request_id,
      order_by: [asc: rc.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def create_comment(attrs \\ %{}) do
    %RequestComment{}
    |> RequestComment.changeset(attrs)
    |> Repo.insert()
  end

  def delete_comment(%RequestComment{} = comment) do
    Repo.delete(comment)
  end
end
