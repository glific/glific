defmodule Glific.Repo.Migrations.AddGcsColumn do
  use Ecto.Migration

  def change do
    add_gcs_url_to_message_media()

    gcs_jobs()
  end

  defp add_gcs_url_to_message_media() do
    alter table(:messages_media) do
      # gcs url
      add :gcs_url, :text, null: true
    end
  end

  defp gcs_jobs do
    create table(:gcs_jobs) do
      # references the last message media we processed
      add :message_media_id, references(:messages_media, on_delete: :nilify_all), null: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gcs_jobs, :organization_id)
    create unique_index(:gcs_jobs, :message_media_id)
  end
end
