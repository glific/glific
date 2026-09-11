defmodule Glific.Repo.Migrations.AddChannelToContactHistories do
  use Ecto.Migration

  def up do
    alter table(:contact_histories) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment: "The channel the event that produced this history row came from."
    end
  end

  def down do
    alter table(:contact_histories) do
      remove :channel
    end
  end
end
