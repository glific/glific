defmodule Glific.Repo.Migrations.AlertMessagesMediaTableWithUrl do
  use Ecto.Migration

  alias Glific.Enums.MediaType

  def up do
    MediaType.create_type()
    add_media_type()
  end

  def down do
    MediaType.drop_type()
  end

  defp add_media_type do
    alter table(:messages_media) do
      add(:media_type, :media_type_enum,
        null: false,
        default: "document",
        comment: "Media type of the message"
      )
    end
  end
end
