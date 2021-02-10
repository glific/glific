defmodule Glific.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    # We might have manually created this on our production servers
    # hence using if not exists
    create_if_not_exists index(:contacts, :last_communication_at)

    create_if_not_exists index(:flow_contexts, [:wakeup_at, :completed_at])

    create_if_not_exists index(:flow_revisions, :flow_id)
    create_if_not_exists index(:flow_revisions, :status)
    create_if_not_exists index(:flow_revisions, :organization_id)

    create_if_not_exists index(:messages, :inserted_at)
    create_if_not_exists index(:messages, :updated_at)
    execute("""
    CREATE INDEX IF NOT EXISTS messages_body_idx_gin ON messages USING gin (body gin_trgm_ops);
    """)

    create_if_not_exists index(:search_messages, :contact_id)
  end
end
