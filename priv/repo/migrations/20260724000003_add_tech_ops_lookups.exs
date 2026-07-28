defmodule Hermes.Repo.Migrations.AddTechOpsLookups do
  use Ecto.Migration

  @moduledoc """
  Replaces the free-text `reporter` and `issue_origin` columns on
  `tech_ops_tasks` with managed lookup tables so values stay canonical across
  the UI (and, later, API writers). Existing free-text values are backfilled
  into the lookups, deduplicated on a normalized key (trim + lowercase +
  collapsed whitespace).
  """

  def up do
    create table(:tech_ops_reporters) do
      add :name, :string, null: false
      add :normalized, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tech_ops_reporters, [:normalized])

    create table(:tech_ops_issue_origins) do
      add :name, :string, null: false
      add :normalized, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tech_ops_issue_origins, [:normalized])

    alter table(:tech_ops_tasks) do
      add :reporter_id, references(:tech_ops_reporters, on_delete: :nilify_all)
      add :issue_origin_id, references(:tech_ops_issue_origins, on_delete: :nilify_all)
    end

    create index(:tech_ops_tasks, [:reporter_id])
    create index(:tech_ops_tasks, [:issue_origin_id])

    # Backfill: seed lookups from existing free-text values (deduped by
    # normalized key) and repoint tasks at the new rows.
    execute """
    INSERT INTO tech_ops_reporters (name, normalized, inserted_at, updated_at)
    SELECT DISTINCT ON (lower(btrim(regexp_replace(reporter, '\\s+', ' ', 'g'))))
           btrim(reporter),
           lower(btrim(regexp_replace(reporter, '\\s+', ' ', 'g'))),
           now(), now()
    FROM tech_ops_tasks
    WHERE reporter IS NOT NULL AND btrim(reporter) <> ''
    ORDER BY lower(btrim(regexp_replace(reporter, '\\s+', ' ', 'g'))), btrim(reporter)
    """

    execute """
    INSERT INTO tech_ops_issue_origins (name, normalized, inserted_at, updated_at)
    SELECT DISTINCT ON (lower(btrim(regexp_replace(issue_origin, '\\s+', ' ', 'g'))))
           btrim(issue_origin),
           lower(btrim(regexp_replace(issue_origin, '\\s+', ' ', 'g'))),
           now(), now()
    FROM tech_ops_tasks
    WHERE issue_origin IS NOT NULL AND btrim(issue_origin) <> ''
    ORDER BY lower(btrim(regexp_replace(issue_origin, '\\s+', ' ', 'g'))), btrim(issue_origin)
    """

    execute """
    UPDATE tech_ops_tasks t
    SET reporter_id = r.id
    FROM tech_ops_reporters r
    WHERE r.normalized = lower(btrim(regexp_replace(t.reporter, '\\s+', ' ', 'g')))
      AND t.reporter IS NOT NULL AND btrim(t.reporter) <> ''
    """

    execute """
    UPDATE tech_ops_tasks t
    SET issue_origin_id = o.id
    FROM tech_ops_issue_origins o
    WHERE o.normalized = lower(btrim(regexp_replace(t.issue_origin, '\\s+', ' ', 'g')))
      AND t.issue_origin IS NOT NULL AND btrim(t.issue_origin) <> ''
    """

    alter table(:tech_ops_tasks) do
      remove :reporter
      remove :issue_origin
    end
  end

  def down do
    alter table(:tech_ops_tasks) do
      add :reporter, :string
      add :issue_origin, :string
    end

    execute """
    UPDATE tech_ops_tasks t
    SET reporter = r.name
    FROM tech_ops_reporters r
    WHERE t.reporter_id = r.id
    """

    execute """
    UPDATE tech_ops_tasks t
    SET issue_origin = o.name
    FROM tech_ops_issue_origins o
    WHERE t.issue_origin_id = o.id
    """

    alter table(:tech_ops_tasks) do
      remove :reporter_id
      remove :issue_origin_id
    end

    drop table(:tech_ops_issue_origins)
    drop table(:tech_ops_reporters)
  end
end
