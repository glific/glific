defmodule Glific.Repo.Migrations.Stats do
  use Ecto.Migration

  def up do
    stats()
  end

  defp stats do
    # lets drop the tables from the DB if it exists
    # since we are starting off with a blank slate
    drop_if_exists table(:stats)

    # daily trends, capture once a day
    create table(:stats_daily) do
      # contact related data
      add :contacts, :integer, comment: "Total number of contacts"
      add :active, :integer, comment: "Total number of active contacts"
      add :optin, :integer, comment: "Number of opted in contacts"
      add :optout, :integer, comment: "Number of opted out contacts"

      # message related data
      add :messages, :integer, comment: "Total number of messages"
      add :inbound, :integer, comment: "Total number of inbound messages"
      add :outbound, :integer, comment: "Total number of outbound messages"
      add :hsm, :integer, comment: "Total number of outbound messages"

      add :flows_started, :integer, comment: "Total number of flows started today"
      add :flows_completed, :integer, comment: "Total number of flows completed today"

      add :date, :date, comment: "All stats are measured with respect to UTC time, to keep things timezone agnostic"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stats_daily, :organization_id)
    create index(:stats_daily, :date)

    # hourly trends
    create table(:stats_hourly) do
      add :active, :integer, comment: "Number of contacts active this period"

      add :inbound, :integer, comment: "Number of inbound messages this period"
      add :outbound, :integer, comment: "Number of outbound messages this period"
      add :hsm, :integer, comment: "Number of HSM messages (outbound only) this period"

      add :flows_started, :integer, comment: "Number of flows started this period"
      add :flows_completed, :integer, comment: "Number of flows completed this period"

      add :date, :date, comment: "All stats are measured with respect to UTC time, to keep things timezone agnostic"
      add :time, :integer, comment: "The start of the hour that this record represents, 0..23"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stats_hourly, :organization_id)
    create index(:stats_hourly, :date)
  end

  def down do
    drop table(:stats)
  end
end
