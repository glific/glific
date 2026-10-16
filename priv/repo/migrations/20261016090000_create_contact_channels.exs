defmodule Glific.Repo.Migrations.CreateContactChannels do
  @moduledoc """
  Per-channel state of a contact, starting with consent: one row per `(contact, channel)`.
  `contacts.optin_*` stays the WhatsApp consent record; this table is where a channel without
  those columns (web first) records what the person agreed to.
  """
  use Ecto.Migration

  def change do
    create table(:contact_channels,
             comment: "Per-channel state of a contact, such as consent to be messaged on it"
           ) do
      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "The contact (person) this state belongs to"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :channel, :message_channel_enum,
        null: false,
        comment: "Channel this state is for"

      add :optin_time, :utc_datetime,
        comment: "When the contact first agreed to be messaged on this channel"

      add :optin_method, :string, comment: "How the contact opted in on this channel"

      add :optout_time, :utc_datetime,
        comment: "When the contact last opted out on this channel; cleared on a later opt-in"

      add :optout_method, :string, comment: "How the contact opted out on this channel"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contact_channels, [:contact_id, :channel])
    create index(:contact_channels, [:organization_id, :channel])
  end
end
