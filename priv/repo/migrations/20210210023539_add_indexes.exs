defmodule Glific.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    # We might have manually created this on our production servers
    # hence using if not exists
    create_if_not_exists index(:search_messages, :contact_id)

    create_if_not_exists index(:flow_contexts, [:wakeup_at, :completed_at])

    create_if_not_exists index(:messages, :inserted_at)
    create_if_not_exists index(:messages, :updated_at)

    create_if_not_exists index(:flow_revisions, :flow_id)
    create_if_not_exists index(:flow_revisions, :status)
    create_if_not_exists index(:flow_revisions, :organization_id)
  end
end
