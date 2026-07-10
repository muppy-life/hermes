defmodule Hermes.Repo.Migrations.AddDeletedAtToUsers do
  use Ecto.Migration

  # Explicit up/0 and down/0 (rather than change/0) because the index swap is
  # not safely auto-reversible: once a soft-deleted user's email has been reused
  # by a new active account, auto-recreating the plain unique index on rollback
  # would fail on the duplicate email. down/0 drops the deleted_at column first
  # (which makes soft-deletes impossible), then restores the original plain
  # unique index — safe because no duplicate active emails can exist.

  def up do
    alter table(:users) do
      add :deleted_at, :utc_datetime
    end

    # Replace the plain unique email index with a partial one scoped to active
    # (non-deleted) users, so a soft-deleted user's email can be reused.
    drop_if_exists unique_index(:users, [:email])

    create unique_index(:users, [:email],
             where: "deleted_at IS NULL",
             name: :users_email_active_index
           )

    create index(:users, [:deleted_at])
  end

  def down do
    drop_if_exists index(:users, [:deleted_at])
    drop_if_exists unique_index(:users, [:email], name: :users_email_active_index)

    # Drop the column before restoring the plain unique index: without
    # deleted_at there is no soft-delete concept to scope on. Note that if an
    # email was reused while a soft-deleted row still held it, two rows now
    # share that email and this index creation will fail — such data must be
    # de-duplicated by hand before rolling back.
    alter table(:users) do
      remove :deleted_at
    end

    create unique_index(:users, [:email])
  end
end
