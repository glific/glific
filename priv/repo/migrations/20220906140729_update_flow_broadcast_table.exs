defmodule Glific.Repo.Migrations.UpdateFlowBroadcastTable do
  use Ecto.Migration

  def change do
    rename_tables()
    rename_columns()

    alter table(:message_broadcasts) do
      add :type, :string, comment: "type of the broadcast."

      add :message_params, :jsonb,
        null: true,
        comment: "Messages attrs in case of message broadcast"
    end

    alter table(:message_broadcasts) do
      modify :flow_id, references(:flows, on_delete: :delete_all), null: true, comment: "Flow ID"
    end
  end

  defp rename_tables() do
    rename(table(:flow_broadcasts), to: table(:message_broadcasts))
    rename(table(:flow_broadcast_contacts), to: table(:message_broadcast_contacts))
  end

  defp rename_columns() do
    rename table(:messages), :flow_broadcast_id, to: :message_broadcast_id
    rename table(:flow_contexts), :flow_broadcast_id, to: :message_broadcast_id
    rename table(:message_broadcast_contacts), :flow_broadcast_id, to: :message_broadcast_id
  end
end
