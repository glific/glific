defmodule Glific.Repo.Migrations.AddFlowContextInWebhookLogs do
  use Ecto.Migration

  def change do
    alter table(:webhook_logs) do
      add :flow_context_id,
          references(:flow_contexts, on_delete: :delete_all),
          null: true
    end

    create index(:webhook_logs, [:flow_context_id], where: "flow_context_id IS NOT NULL")
  end
end
