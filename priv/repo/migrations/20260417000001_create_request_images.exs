defmodule Hermes.Repo.Migrations.CreateRequestImages do
  use Ecto.Migration

  def change do
    create table(:request_images) do
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:request_images, [:request_id])
    create unique_index(:request_images, [:key])
  end
end
