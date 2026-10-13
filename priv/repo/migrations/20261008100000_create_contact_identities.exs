defmodule Glific.Repo.Migrations.CreateContactIdentities do
  @moduledoc """
  How a contact logs in on a channel: one row per login, each pointing at the contact (the person).
  The `identifier` (a WhatsApp phone, a username issued by the NGO, later a Telegram chat id) is
  unique within an organization and channel; web usernames are stored lowercase and limited to
  letters, digits, `_`, `@` and `.`.
  """
  use Ecto.Migration

  def change do
    create table(:contact_identities,
             comment: "Channel identifiers of a contact; the contact itself stays the person"
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
        comment:
          "Login identifier on the channel; web usernames are stored lowercase and limited to letters, digits, _, @ and ."

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:contact_identities, [:organization_id, :channel, :identifier])
    create index(:contact_identities, [:contact_id])
  end
end
