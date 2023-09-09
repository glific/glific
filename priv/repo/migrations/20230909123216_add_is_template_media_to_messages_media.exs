defmodule Glific.Repo.Migrations.AddIsTemplateMediaToMessagesMedia do
  use Ecto.Migration

  def up do
    alter table(:messages_media) do
      add :is_template_media, :boolean
      remove :provider_media_id
    end
  end

  def down do
    alter table(:messages_media) do
      remove :is_template_media
    end
  end
end
