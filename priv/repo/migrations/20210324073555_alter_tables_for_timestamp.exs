defmodule Glific.Repo.Migrations.AlterTablesForTimestamp do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      modify :inserted_at, :utc_datetime_usec,
        comment: "Time when the record entry was first made"

      modify :updated_at, :utc_datetime_usec,
        comment: "Time when the record entry was last updated"
    end

    alter table(:flows) do
      modify :inserted_at, :utc_datetime_usec,
        comment: "Time when the record entry was first made"

      modify :updated_at, :utc_datetime_usec,
        comment: "Time when the record entry was last updated"
    end

    alter table(:flow_results) do
      modify :inserted_at, :utc_datetime_usec,
        comment: "Time when the record entry was first made"

      modify :updated_at, :utc_datetime_usec,
        comment: "Time when the record entry was last updated"
    end
  end
end
