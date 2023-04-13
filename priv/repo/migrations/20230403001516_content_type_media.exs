defmodule Glific.Repo.Migrations.ContentTypeMedia do
  use Ecto.Migration

  def change do
    add_content_type_to_message_media()
  end

  defp add_content_type_to_message_media() do
    alter table(:messages_media) do
      # content type string
      add(:content_type, :string,
        null: true,
        comment: "Content Type for the media message sent by WABA"
      )
    end
  end
end
