defmodule Glific.Repo.Migrations.MessageNumberStatus do
  use Ecto.Migration

  def change do
    drop_if_exists table(:search_messages)
    drop_search_message_code()

    alter table(:contacts) do
      add :is_org_read, :boolean,
        default: true,
        comment: "Has a staff read the messages sent by this contact"

      add :is_org_replied, :boolean,
        default: true,
        comment: "Has a staff or flow replied to the messages sent by this contact"

      add :is_contact_replied, :boolean,
        default: true,
        comment: "Has the contact replied to the messages sent by the system"

      add :last_message_number, :integer,
        default: 0,
        comment: "The max message number recd or sent by this contact"
    end

    alter table(:messages) do
      remove_if_exists(:is_read, :boolean)
      remove_if_exists(:is_replied, :boolean)
    end

    alter table(:groups) do
      add :last_message_number, :integer,
        default: 0,
        comment: "The max message number sent via this group"
    end
  end

  defp drop_search_message_code do
    [
      "DROP TRIGGER IF EXISTS update_search_message_trigger ON  contacts",
      "DROP TRIGGER IF EXISTS update_search_message_trigger ON messages",
      "DROP TRIGGER IF EXISTS update_search_message_trigger ON messages_tags",
      "DROP FUNCTION IF EXISTS create_search_messages",
      "DROP FUNCTION IF EXISTS update_search_messages_on_messages_update",
      "DROP FUNCTION IF EXISTS update_search_messages_on_contacts_update",
      "DROP FUNCTION IF EXISTS update_search_messages_on_messages_tags_update"
    ]
    |> Enum.each(&execute/1)
  end
end
