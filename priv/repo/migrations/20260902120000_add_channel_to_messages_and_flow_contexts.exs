defmodule Glific.Repo.Migrations.AddChannelToMessagesAndFlowContexts do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TYPE message_channel_enum AS ENUM (
      'whatsapp',
      'web'
    )
    """)

    alter table(:messages) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment: "The channel a message was sent or received on."
    end

    alter table(:flow_contexts) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment:
          "The channel of the message that triggered this flow context; propagated into the flow's outbound sends so replies route back over the originating channel."
    end
  end

  def down do
    alter table(:messages) do
      remove :channel
    end

    alter table(:flow_contexts) do
      remove :channel
    end

    execute("DROP TYPE IF EXISTS message_channel_enum")
  end
end
