defmodule Glific.Repo.Migrations.V0_8_7_AlterGlificTables do
  use Ecto.Migration

  def change do
    add_group_id_to_messages()

    add_last_communication_at_to_groups()

    add_flow_context_to_results()
  end

  defp add_group_id_to_messages() do
    alter table(:messages) do
      # add group_id to record messages sent to a group
      add :group_id, references(:groups, on_delete: :delete_all), null: true, comment: "Group ID with which the message is associated"
    end
  end

  defp add_last_communication_at_to_groups() do
    alter table(:groups) do
      # field can be used to sort group conversations
      add :last_communication_at, :utc_datetime, comment: "Timestamp of the most recent communication"
    end
  end

  defp add_flow_context_to_results() do
    alter table(:flow_results) do
      # this is not a foreign key
      add :flow_context_id, :bigint, comment: "Flow context that a contact is in with resperct to a flow; this is not a foreign key"
    end

    drop index(:flow_results, [:contact_id, :flow_id, :flow_version])
    create unique_index(:flow_results, :flow_context_id)
  end
end
