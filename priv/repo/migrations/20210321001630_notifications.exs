defmodule Glific.Repo.Migrations.Notifications do
  use Ecto.Migration

  def up do
    notifications()
  end

  defp notifications do
    # lets drop the tables from the DB if it exists
    # since we are starting off with a blank slate
    drop_if_exists table(:notifications)

    create table(:notifications) do
      # we'll create a generic json map for the referring entities, since this could be varied
      # so typically, we'll have
      # contact: {contact_id, name, phone}, flow: {flow_id, flow_name}, group: {group_id, group_name}
      # we add details since the DB values change over time, also different notifications will
      # add more data (like failure to send message will include bsp_status of the contact)
      add :entity, :jsonb,
        default: "{}",
        comment: "A map of objects that are involved in this notification"

      add :category, :string,
        comment: "The category that this falls under: Flow, Message, BigQuery, etc"

      add :message, :text, comment: "The specific error message that caused this notification"

      add :severity, :text,
        default: "Error",
        comment: "The severity level. We'll include a few info notifications"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, :organization_id)
    create index(:notifications, :inserted_at)
  end

  def down do
    drop table(:notifications)
  end
end
