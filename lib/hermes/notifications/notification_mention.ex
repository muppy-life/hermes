defmodule Hermes.Notifications.NotificationMention do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_mentions" do
    belongs_to :notification, Hermes.Notifications.Notification
    belongs_to :comment, Hermes.Requests.RequestComment
    belongs_to :request, Hermes.Requests.Request
    belongs_to :mentioned_by_user, Hermes.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:notification_id, :comment_id, :request_id, :mentioned_by_user_id])
    |> validate_required([:notification_id, :comment_id, :request_id])
    |> foreign_key_constraint(:notification_id)
    |> foreign_key_constraint(:comment_id)
    |> foreign_key_constraint(:request_id)
    |> foreign_key_constraint(:mentioned_by_user_id)
    |> unique_constraint(:notification_id)
  end
end
