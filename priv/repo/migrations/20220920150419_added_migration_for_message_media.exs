defmodule Glific.Repo.Migrations.AddedMigrationForMessageMedia do
  use Ecto.Migration

   def change do
    alter table(:messages_media) do
      add :media_type, :media_type_enum, comment: "Media type of message options are audio, document,
      image, video, sticker"
    end
  end
end
