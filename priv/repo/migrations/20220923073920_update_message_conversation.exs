defmodule Glific.Repo.Migrations.UpdateMessageConversation do
  use Ecto.Migration

  def change do
    modify :message_id, references(:messages, on_delete: :nilify_all),
        null: true,
        comment: "reference for the message"
  end
end
