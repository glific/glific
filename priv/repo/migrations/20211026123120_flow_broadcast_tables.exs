defmodule Glific.Repo.Migrations.FlowBroadcastTables do
  use Ecto.Migration

  def change do
    flow_broadcasts()
    flow_broadcast_contacts()
  end

  defp flow_broadcasts() do
    create table(:flow_broadcasts,
             comment:
               "This table is populated when the user schedules a flow on a collection (or when we trigger a flow on a collection)"
           ) do
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all), null: false

      add :message_id, references(:messages, on_delete: :nilify_all),
        null: true,
        comment: "If this message was sent to a group"

      add :user_id, references(:users, on_delete: :nilify_all),
        null: true,
        comment: "User who started the flow"

      add :organization_id, references(:organizations, on_delete: :delete_all)

      add :started_at, :utc_datetime, null: true, default: nil
      add :completed_at, :utc_datetime, null: true, default: nil

      timestamps(type: :utc_datetime)
    end
  end

  defp flow_broadcast_contacts() do
    create table(:flow_broadcast_contacts,
             comment:
               "This table is populated when the user schedules a flow on a collection (or when we trigger a flow on a collection)"
           ) do
      add :flow_broadcast_id, references(:flow_broadcasts, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :status, :string, null: true
      add :organization_id, references(:organizations, on_delete: :delete_all)
      add :processed_at, :utc_datetime, null: true, default: nil

      timestamps(type: :utc_datetime)
    end
  end
end
