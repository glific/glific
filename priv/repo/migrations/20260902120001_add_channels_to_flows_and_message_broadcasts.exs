defmodule Glific.Repo.Migrations.AddChannelsToFlowsAndMessageBroadcasts do
  use Ecto.Migration

  def up do
    alter table(:flows) do
      add :channels, {:array, :message_channel_enum},
        default: ["whatsapp"],
        null: false,
        comment:
          "The set of channels this flow can reach. Derived from the flow definition on every save, never authored. The default is whatsapp alone because it represents the un-derived state, not a narrowing: every existing flow demonstrably works on whatsapp today, and web is earned once the derivation has run and found every node compatible."
    end

    alter table(:message_broadcasts) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment:
          "The channel a scheduled or group-initiated flow start runs on. Persisted rather than passed in opts because the broadcast worker rebuilds its opts from this row in a later process."
    end
  end

  def down do
    alter table(:flows) do
      remove :channels
    end

    alter table(:message_broadcasts) do
      remove :channel
    end
  end
end
