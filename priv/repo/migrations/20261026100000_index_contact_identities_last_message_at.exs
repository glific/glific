defmodule Glific.Repo.Migrations.IndexContactIdentitiesLastMessageAt do
  @moduledoc """
  The inbox ordering and the hourly session expiry will filter and sort contacts by the `last_message_at` of
  their WhatsApp identity, where they use `contacts.last_message_at`. The index is plain, not partial: the
  inbox sorts descending, which puts nulls first and so could not be served by a `NOT NULL` partial index.

  `contact_identities` is still small when this runs on boot, before the backfill fills it, so the table lock
  is short.
  """
  use Ecto.Migration

  def change do
    create index(:contact_identities, [:organization_id, :channel, :last_message_at],
             comment: "Inbox ordering and session expiry by last inbound message on a channel"
           )
  end
end
