defmodule Glific.Repo.Migrations.AddUpdatedAtColumnForBigquery do
  use Ecto.Migration

  def change do
    alter table(:bigquery_jobs) do
      add :last_updated_at, :utc_datetime_usec,
        comment: "Time when the record updated on bigquery"
    end
  end
end
