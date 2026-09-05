defmodule Glific.Repo.Migrations.AddChannelsToFlowsAndMessageBroadcasts do
  use Ecto.Migration

  def up do
    alter table(:flows) do
      add :channels, {:array, :message_channel_enum},
        default: ["whatsapp", "web"],
        null: false,
        comment:
          "The set of channels this flow can reach. Derived from the flow definition on every save, never authored: a flow narrows to web-only once a node sends a blocks interactive template, to whatsapp-only when a node broadcasts or sends a template, and is omnichannel otherwise."
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
