defmodule Glific.Repo.Migrations.AddLastUpdatedIdToBigqueryJobs do
  @moduledoc """
  Adds the id half of the BigQuery update-sync cursor.

  `last_updated_at` alone cannot address a row when bulk `update_all` stamps thousands of
  rows with an identical `updated_at`. Pairing it with the row id makes the cursor a total
  order, so a sync tick can bound how many rows it fetches without skipping the tied ones.

  bigquery_jobs is a small bookkeeping table (one row per synced table per org), so the
  non-null default is cheap here.
  """

  use Ecto.Migration

  def change do
    alter table(:bigquery_jobs) do
      add :last_updated_id, :bigint,
        null: false,
        default: 0,
        comment: "Id of the last row synced at last_updated_at; tie-breaker for the update cursor"
    end
  end
end
