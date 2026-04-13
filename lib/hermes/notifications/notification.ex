defmodule Hermes.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(mention)

  schema "notifications" do
    field :type, :string
    field :read_at, :utc_datetime

    belongs_to :user, Hermes.Accounts.User

    has_one :mention_detail, Hermes.Notifications.NotificationMention

    timestamps()
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :type, :read_at])
    |> validate_required([:user_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> foreign_key_constraint(:user_id)
  end
end
