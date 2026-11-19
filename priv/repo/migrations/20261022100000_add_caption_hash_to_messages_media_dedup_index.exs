defmodule Glific.Repo.Migrations.AddCaptionHashToMessagesMediaDedupIndex do
  use Ecto.Migration

  # Concurrent index builds cannot run inside a transaction or hold the Ecto
  # migration advisory lock — required on the large production messages_media table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # The if_(not_)exists forms let a run that stopped halfway be retried, and make a
  # second node racing on the unlocked migration a no-op instead of a crash.
  def up do
    # Backs the media dedup lookup in Messages.do_create_message_media/2. Without the
    # caption in the key, a URL sent with many personalized captions makes every
    # lookup scan all of that URL's rows. md5 keeps the key fixed-size, so long
    # captions cannot overflow the btree row limit (glific#5319).
    create_if_not_exists index(:messages_media, [:organization_id, :url, "md5(caption)"],
                           name: :messages_media_organization_id_url_caption_md5_index,
                           concurrently: true,
                           comment: "Backs media dedup lookup by org + url + caption hash"
                         )

    # Its (organization_id, url) prefix is covered by the index above.
    drop_if_exists index(:messages_media, [:organization_id, :url], concurrently: true)
  end

  def down do
    # Restore the old index before dropping the new one, so the lookup is never unindexed.
    create_if_not_exists index(:messages_media, [:organization_id, :url],
                           concurrently: true,
                           comment: "Backs media dedup lookup by org + url (glific#5319)"
                         )

    drop_if_exists index(:messages_media, [:organization_id, :url, "md5(caption)"],
                     name: :messages_media_organization_id_url_caption_md5_index,
                     concurrently: true
                   )
  end
end
