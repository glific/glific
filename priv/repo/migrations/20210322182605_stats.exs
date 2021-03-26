defmodule Glific.Repo.Migrations.Stats do
  use Ecto.Migration

  def up do
    stats()
  end

  defp stats do
    # lets drop the tables from the DB if it exists
    # since we are starting off with a blank slate
    drop_if_exists table(:stats)

    # period trends, capture hourly, daily, weekly, monthly, summary
    # The total is specific only for that period
    # The summary total is the grand total in the DB, and keeps track of contact data only
    create table(:stats) do
      # contact related data
      add :contacts, :integer, comment: "Total number of contacts in the system. This is the only absolute number in non-summary records"

      add :active, :integer, comment: "Total number of active contacts"
      add :optin, :integer, comment: "Number of opted in contacts"
      add :optout, :integer, comment: "Number of opted out contacts"

      # message related data
      add :messages, :integer, comment: "Total number of messages"
      add :inbound, :integer, comment: "Total number of inbound messages"
      add :outbound, :integer, comment: "Total number of outbound messages"
      add :hsm, :integer, comment: "Total number of HSM messages (outbound only)"

      add :flows_started, :integer, comment: "Total number of flows started today"
      add :flows_completed, :integer, comment: "Total number of flows completed today"

      add :users, :integer, comment: "Total number of users active"

      add :period, :string, comment: "The period for this record: hour, day, week, month, summary"

      add :date, :date,
        comment:
          "All stats are measured with respect to UTC time, to keep things timezone agnostic"

      add :hour, :integer,
        comment: "The hour that this record represents, 0..23, only for PERIOD: hour"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stats, :organization_id)
    create index(:stats, :date)
  end

  def down do
    drop table(:stats)
  end
end
