defmodule Glific.Repo.Migrations.AddChannelToFlows do
  use Ecto.Migration

  def up do
    alter table(:flows) do
      add :channel, :message_channel_enum,
        default: "whatsapp",
        null: false,
        comment:
          "The channel this flow runs on, chosen when the flow is created. Authored rather than derived, because the channel decides which nodes the editor offers — it has to be known before there are nodes to derive it from."

      remove :channels
    end
  end

  def down do
    alter table(:flows) do
      remove :channel

      add :channels, {:array, :message_channel_enum},
        default: ["whatsapp"],
        null: false,
        comment: "The set of channels this flow can reach."
    end
  end
end
