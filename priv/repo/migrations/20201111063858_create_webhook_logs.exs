defmodule Glific.Repo.Migrations.CreateWebhookLogs do
  use Ecto.Migration

  def change do
    create table(:webhook_logs) do
      add :request_json, :jsonb, default: "{}", null: false
      add :response_json, :jsonb, default: "{}", null: true

      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      # We store flows with both id and uuid, since floweditor always refers to a flow by its uuid
      add :flow_uuid, :uuid, null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

  end
end
