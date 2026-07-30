defmodule Glific.Repo.Migrations.AddChannelToFlowContexts do
  use Ecto.Migration

  def change do
    alter table(:flow_contexts) do
      add :channel, :string,
        default: "whatsapp",
        null: false,
        comment:
          "The channel (whatsapp, web, ...) of the message that triggered this flow context; propagated into the flow's outbound sends so replies route back over the originating channel."
    end
  end
end
