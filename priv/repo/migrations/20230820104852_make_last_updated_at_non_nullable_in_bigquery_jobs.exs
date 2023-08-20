defmodule Glific.Repo.Migrations.MakeLastUpdatedAtNonNullableInBigqueryJobs do
  use Ecto.Migration

  def up do
    alter table(:bigquery_jobs) do
      modify :last_updated_at, :timestamp, null: false, default: fragment("NOW()")
    end
  end

  def down do
    alter table(:bigquery_jobs) do
      modify :last_updated_at, :timestamp, null: true, default: nil
    end
  end
end
