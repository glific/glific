defmodule Glific.Repo.Migrations.UpdateFlowBroadcastTable do
  use Ecto.Migration

  def change do
    rename(table(:flow_broadcasts), to: table(:message_broadcasts))

    alter table(:message_broadcasts) do
      add :type, :string, comment: "type of the broadcast."
    end
  end
end
