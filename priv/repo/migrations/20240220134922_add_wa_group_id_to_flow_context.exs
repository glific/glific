defmodule Glific.Repo.Migrations.AddWaGroupIdToFlowContext do
  use Ecto.Migration

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      add :wa_group_id, references(:wa_groups, on_delete: :delete_all),
        null: true,
        comment: "ID of WA group messages are sent/received from"

      modify :contact_id, :bigint, null: true
    end
  end
end
