defmodule Glific.Repo.Migrations.AddMediaTypeToMessageTable do
  use Ecto.Migration

  def change do
    alter table(messages_media) do
      add :media_type, :media_message_type_enum, comment: "Media type of message options are audio, contact,
      document, hsm, image, location, list, quick_reply, text, video, sticker"
    end
  end
end
