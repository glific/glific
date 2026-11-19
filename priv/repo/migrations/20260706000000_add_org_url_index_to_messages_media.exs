defmodule Glific.Repo.Migrations.AddOrgUrlIndexToMessagesMedia do
  use Ecto.Migration

  # Concurrent index build cannot run inside a transaction or hold the Ecto
  # migration advisory lock — required for a zero-downtime build on the large
  # production messages_media table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Backs the media dedup lookup in Messages.do_create_message_media/2, which
    # matches on (organization_id, url). organization_id leads because
    # Repo.prepare_query auto-injects it into every query, so it is always the
    # first predicate. Non-unique: production already has many rows sharing
    # (organization_id, url) with different captions, so a unique index cannot be
    # built over the existing data.
    #
    # This stands in for the ad-hoc, production-only
    # messages_media_url_organization_id_caption_index, whose full-caption btree
    # key overflowed the 2704-byte limit and crashed inbound media inserts on
    # long captions (glific#5319). That old index was never created by a
    # migration, so it is dropped directly on production rather than here.
    create index(:messages_media, [:organization_id, :url],
             concurrently: true,
             comment: "Backs media dedup lookup by org + url (glific#5319)"
           )
  end
end
