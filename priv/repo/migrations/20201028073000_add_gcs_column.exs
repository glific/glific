defmodule Glific.Repo.Migrations.AddGcsColumn do
  use Ecto.Migration

  def change do
    add_gcs_url_to_message_media()
  end

  @doc """
  Create new coulmn for GCS URL in message media table
  """
  def add_gcs_url_to_message_media() do
    alter table(:messages_media) do
      # gcs url
      add :gcs_url, :text, null: true
    end
  end
end
