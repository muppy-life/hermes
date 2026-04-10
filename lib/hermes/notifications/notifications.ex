defmodule Hermes.Notifications do
  @moduledoc """
  Context for managing in-app notifications.

  Handles creation and querying of notifications and their typed detail records.
  Email delivery is handled separately by `Hermes.Notifications.Email`.
  """

  import Ecto.Query, warn: false

  alias Hermes.Notifications.Notification
  alias Hermes.Notifications.NotificationMention
  alias Hermes.Repo

  @doc """
  Creates a mention notification for a user, along with its detail record.

  ## Parameters

    * `user_id` - The ID of the user being notified
    * `comment` - The comment containing the mention (with `:request` preloaded)
    * `mentioned_by_user_id` - The ID of the user who wrote the mention

  ## Returns

    * `{:ok, notification}` with `mention_detail` preloaded
    * `{:error, changeset}` on failure
  """
  def create_mention_notification(user_id, comment, mentioned_by_user_id) do
    Repo.transaction(fn ->
      notification =
        %Notification{}
        |> Notification.changeset(%{user_id: user_id, type: "mention"})
        |> Repo.insert!()

      %NotificationMention{}
      |> NotificationMention.changeset(%{
        notification_id: notification.id,
        comment_id: comment.id,
        request_id: comment.request_id,
        mentioned_by_user_id: mentioned_by_user_id
      })
      |> Repo.insert!()

      Repo.preload(notification, :mention_detail)
    end)
  end

  @doc """
  Returns all unread notifications for a user, with type-specific details preloaded.
  """
  def list_unread_notifications(user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at),
      order_by: [desc: n.inserted_at],
      preload: [mention_detail: [:comment, :request, :mentioned_by_user]]
    )
    |> Repo.all()
  end

  @doc """
  Returns all notifications for a user, with type-specific details preloaded.
  """
  def list_notifications(user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.inserted_at],
      preload: [mention_detail: [:comment, :request, :mentioned_by_user]]
    )
    |> Repo.all()
  end

  @doc """
  Marks a notification as read. Returns `{:error, :not_found}` if the notification
  does not belong to the given user.
  """
  def mark_as_read(%Notification{} = notification, user_id)
      when notification.user_id == user_id do
    notification
    |> Notification.changeset(%{read_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def mark_as_read(_, _), do: {:error, :not_found}

  @doc """
  Counts unread notifications for a user.
  """
  def unread_count(user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at),
      select: count(n.id)
    )
    |> Repo.one()
  end
end
