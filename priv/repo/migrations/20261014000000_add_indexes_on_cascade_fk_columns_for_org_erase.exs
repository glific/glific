defmodule Glific.Repo.Migrations.AddIndexesOnCascadeFkColumnsForOrgErase do
  use Ecto.Migration

  # These tables are large in production, so the indexes are built
  # concurrently and outside the migration transaction to avoid holding
  # locks and the Ecto migration advisory lock while the build runs.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # tickets.contact_id references contacts(id) ON DELETE CASCADE.
    # Only tickets_organization_id_index exists today, so deleting a contact
    # forces a sequential scan of the whole tickets table for every row.
    create_if_not_exists index(:tickets, [:contact_id],
                           name: "tickets_contact_id_index",
                           concurrently: true
                         )

    # contacts_wa_groups.contact_id references contacts(id) ON DELETE CASCADE.
    # The only existing index is (wa_group_id, contact_id), where contact_id is
    # not the leading column, so a cascade lookup by contact_id cannot use it.
    create_if_not_exists index(:contacts_wa_groups, [:contact_id],
                           name: "contacts_wa_groups_contact_id_index",
                           concurrently: true
                         )

    # wa_messages.context_message_id references wa_messages(id) ON DELETE CASCADE.
    # There is no index on this column, so the self referencing cascade scans
    # the whole wa_messages table for each deleted row.
    create_if_not_exists index(:wa_messages, [:context_message_id],
                           name: "wa_messages_context_message_id_index",
                           where: "context_message_id IS NOT NULL",
                           concurrently: true
                         )
  end
end
