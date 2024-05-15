defmodule Glific.Repo.Migrations.AddGcsJobType do
  use Ecto.Migration

  def change do
    alter table(:gcs_jobs) do
      add :type, :string,
        null: true,
        default: "incremental",
        comment:
          "can be incremental or unsynced. incremental for normal backup of files to GCS and unsynced to ensure the unsynced files are also backedup later time of day when traffic is low"
    end
  end
end
