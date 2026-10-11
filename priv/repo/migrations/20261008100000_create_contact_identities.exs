defmodule Glific.Repo.Migrations.CreateContactIdentities do
  @moduledoc """
  How a contact logs in on a channel: one row per login, each pointing at the contact (the person).
  The `identifier` is opaque to Glific; `kind` says what it is (a phone, a username issued by the
  NGO), so a username can never collide with a phone on the same channel.
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

      add :kind, :string,
        null: false,
        comment: "What the identifier is: phone or ngo_username"

      add :identifier, :string,
        size: 255,
        null: false,
        comment: "Login identifier on the channel, matched exactly (case-sensitive)"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:contact_identities, [:organization_id, :channel, :kind, :identifier],
             name: :contact_identities_org_channel_kind_identifier_index
           )

    create index(:contact_identities, [:contact_id])
  end
end
