defmodule Glific.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration

  def change do
    add_indexes()
  end

  defp add_indexes() do
    create_if_not_exists(index(:contact_histories, [:contact_id, :updated_at]))
    create_if_not_exists(index(:flow_counts, :flow_id))
    create_if_not_exists(index(:flow_contexts, :updated_at))
    create_if_not_exists(index(:flow_contexts, :parent_id, where: "parent_id IS NOT NULL"))
    create_if_not_exists(index(:message_broadcasts, :flow_id))
    create_if_not_exists(index(:message_broadcasts, :group_id))
    create_if_not_exists(index(:message_broadcast_contacts, :updated_at))
    create_if_not_exists(index(:users, :contact_id))
    create_if_not_exists(index(:webhook_logs, :flow_id))
  end
end
