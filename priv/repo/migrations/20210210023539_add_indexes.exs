defmodule Glific.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    # We might have manually created this on our production servers
    # hence using if not exists
    create_if_not_exists index(:contacts, :last_communication_at)

    create_if_not_exists index(:flow_contexts, :wakeup_at, where: "wakeup_at IS NOT NULL")
    create_if_not_exists index(:flow_contexts, :completed_at, where: "completed_at IS NOT NULL")
    create_if_not_exists index(:flow_contexts, :organization_id)

    create_if_not_exists index(:flow_results, :organization_id)
    create_if_not_exists index(:flow_results, :inserted_at)
    create_if_not_exists index(:flow_results, :updated_at)
    create_if_not_exists index(:flow_results, :flow_id)

    create_if_not_exists index(:messages_media, :organization_id)
    create_if_not_exists index(:triggers, :flow_id)

    create_if_not_exists index(:flow_revisions, :flow_id)
    create_if_not_exists index(:flow_revisions, :status)
    create_if_not_exists index(:flow_revisions, :organization_id)

    create_if_not_exists index(:messages, :flow_id)
    create_if_not_exists index(:messages, :inserted_at)
    create_if_not_exists index(:messages, :updated_at)
    create_if_not_exists index(:messages, :context_message_id)
    create index(:messages, [:group_id], where: "group_id IS NOT NULL")

    ## Removing the indexes which are not in use.
    drop_if_exists index(:messages, :sender_id)
    drop_if_exists index(:messages, :receiver_id)
    drop_if_exists index(:messages, [:organization_id, :contact_id])

    sql = [
      "CREATE EXTENSION IF NOT EXISTS pg_trgm;",
      "CREATE INDEX IF NOT EXISTS messages_body_idx_gin ON messages USING gin (body gin_trgm_ops) WHERE body IS NOT NULL"
    ]

    Enum.each(sql, &execute/1)
  end
end
