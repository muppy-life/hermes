defmodule Hermes.Requests.RequestChange do
  use Ecto.Schema
  import Ecto.Changeset

  schema "request_changes" do
    field :action, :string
    field :field, :string
    field :old_value, :string
    field :new_value, :string
    field :changes, :map

    belongs_to :request, Hermes.Requests.Request
    belongs_to :user, Hermes.Accounts.User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(request_change, attrs) do
    request_change
    |> cast(attrs, [:request_id, :user_id, :action, :field, :old_value, :new_value, :changes])
    |> validate_required([:request_id, :action])
    |> foreign_key_constraint(:request_id)
    |> foreign_key_constraint(:user_id)
  end
end
