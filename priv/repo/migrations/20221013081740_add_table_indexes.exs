defmodule Glific.Repo.Migrations.AddTableIndexes do
  use Ecto.Migration

  def change do
    add_indexes()
    drop_indexes()
  end

  defp add_indexes() do
    create_if_not_exists(index(:contact_histories, :organization_id))
    create_if_not_exists(index(:message_broadcast_contacts, :contact_id))
    create_if_not_exists(index(:message_broadcast_contacts, :organization_id))

    create_if_not_exists(index(:messages, :sender_id))
    create_if_not_exists(index(:messages, :receiver_id))
    create_if_not_exists(index(:messages, :profile_id, where: "(profile_id is NOT null)"))

    create_if_not_exists(
      index(:contacts, :active_profile_id, where: "(active_profile_id is NOT null)")
    )

    create_if_not_exists(index(:flow_contexts, :contact_id))

    create_if_not_exists(index(:message_broadcasts, :updated_at))
    create_if_not_exists(index(:message_broadcasts, :organization_id))
    create_if_not_exists(index(:message_broadcasts, :completed_at))
  end

  defp drop_indexes() do
    drop_if_exists(index(:flow_results, :inserted_at))
    drop_if_exists(index(:messages_conversations, :message_id))
  end
end
