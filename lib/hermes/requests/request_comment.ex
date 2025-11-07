defmodule Hermes.Requests.RequestComment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "request_comments" do
    field :content, :string

    belongs_to :request, Hermes.Requests.Request
    belongs_to :user, Hermes.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(request_comment, attrs) do
    request_comment
    |> cast(attrs, [:request_id, :user_id, :content])
    |> validate_required([:request_id, :user_id, :content])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:request_id)
    |> foreign_key_constraint(:user_id)
  end
end
