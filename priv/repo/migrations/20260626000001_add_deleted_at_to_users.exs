defmodule Hermes.Repo.Migrations.AddDeletedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :deleted_at, :utc_datetime
    end

    # Replace the plain unique index on email with a partial one that only
    # applies to active (non-deleted) users, so a soft-deleted user's email
    # can be reused by a new account.
    drop_if_exists unique_index(:users, [:email])

    create unique_index(:users, [:email],
             where: "deleted_at IS NULL",
             name: :users_email_active_index
           )

    create index(:users, [:deleted_at])
  end
end
