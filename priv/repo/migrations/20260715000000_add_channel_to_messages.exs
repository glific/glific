defmodule Glific.Repo.Migrations.AddChannelToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # discriminator for the channel a message was sent/received on. Contacts
      # are shared across channels; the channel lives on the message only.
      # Kept as a plain string (no PG enum type) so new channels
      # (telegram/rcs/sms/fb_messenger/instagram, ...) need no migration.
      add :channel, :string, default: "whatsapp", null: false
    end

    create index(:messages, [:contact_id, :channel])
  end
end
