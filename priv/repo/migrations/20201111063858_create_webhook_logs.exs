defmodule Glific.Repo.Migrations.CreateWebhookLogs do
  use Ecto.Migration

  def change do
    create table(:webhook_logs) do
      add :url, :string, null: false
      add :method, :string, null: false
      add :request_json, :jsonb, default: "{}"

      add :response_json, :jsonb, default: "{}"
      add :status_code, :integer, null: true
      add :request_headers, :jsonb, default: "[]"

      add :error, :string, null: true

      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
