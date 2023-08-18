defmodule Glific.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:contact_histories, :profile_id, where: "profile_id IS NOT NULL"
    create_if_not_exists index(:bigquery_jobs, [:organization_id, :table])
    create_if_not_exists index(:session_templates, :message_media_id, where: "message_media_id IS NOT NULL"
  end
end
