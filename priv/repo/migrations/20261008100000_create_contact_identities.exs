defmodule Glific.Repo.Migrations.CreateContactIdentities do
  @moduledoc """
  How a contact logs in on a channel: one row per login, each pointing at the contact (the person).
  The `identifier` is opaque to Glific (a phone, a username, later a Telegram chat id), unique within
  an organization and channel.
  """
  use Ecto.Migration

  def change do
    # The foreign key to contacts briefly locks that table; fail fast rather than queue behind a long query.
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    create table(:contact_identities,
             comment: "Channel logins of a contact; the contact itself stays the person"
           ) do
      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "The contact (person) this login belongs to"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :channel, :message_channel_enum,
        null: false,
        comment: "Channel this login is used on"

      add :identifier, :string,
        size: 255,
        null: false,
        comment: "Login identifier on the channel, matched exactly (case-sensitive)"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contact_identities, [:organization_id, :channel, :identifier])
    create index(:contact_identities, [:contact_id])
    create index(:contact_identities, [:organization_id])
  end
end
