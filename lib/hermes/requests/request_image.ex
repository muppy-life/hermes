defmodule Hermes.Requests.RequestImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "request_images" do
    field :key, :string
    field :filename, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :request, Hermes.Requests.Request

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, [:request_id, :key, :filename, :content_type, :size])
    |> validate_required([:request_id, :key, :filename, :content_type, :size])
    |> foreign_key_constraint(:request_id)
    |> unique_constraint(:key)
  end
end
