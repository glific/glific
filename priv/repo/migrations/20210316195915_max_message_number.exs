defmodule Glific.Repo.Migrations.MaxMessageNumber do
  use Ecto.Migration

  def change do
    drop_if_exists table(:search_messages)

    alter table(:contacts) do
      add :last_message_number, :integer, default: 0, comment: "The max message number recd or sent by this contact"
    end

    alter table(:groups) do
      add :last_message_number, :integer, default: 0, comment: "The max message number recd or sent by this contact"
    end
  end
end
