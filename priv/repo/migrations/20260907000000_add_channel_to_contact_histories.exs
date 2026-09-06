defmodule Glific.Repo.Migrations.AddChannelToContactHistories do
  use Ecto.Migration

  def up do
    alter table(:contact_histories) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment: "The channel the event that produced this history row came from."
    end

    create table(:contact_channel_optins) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      add :channel, :message_channel_enum,
        null: false,
        comment: "The channel this consent was given on."

      add :optin_time, :utc_datetime,
        comment: "When the contact consented to being messaged on this channel."

      add :optin_method, :string, comment: "How the consent was obtained, e.g. web_channel."

      add :optout_time, :utc_datetime,
        comment: "When the contact withdrew consent for this channel."

      add :optout_method, :string

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contact_channel_optins, [:contact_id, :channel])
    create index(:contact_channel_optins, [:organization_id, :channel])
  end

  def down do
    drop table(:contact_channel_optins)

    alter table(:contact_histories) do
      remove :channel
    end
  end
end
