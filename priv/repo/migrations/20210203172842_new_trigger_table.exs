defmodule Glific.Repo.Migrations.NewTriggerTable do
  use Ecto.Migration

  def up do
    triggers()
    trigger_logs()
  end

  def down do
    drop table(:trigger_logs)
    drop table(:triggers)
  end

  def triggers() do
    # lets drop the tables from the DB if it exists
    # since we are starting off with a blank slate
    drop_if_exists table(:trigger_logs)
    drop_if_exists table(:triggers)

    create table(:triggers) do
      # Useful to identify triggers by name
      add :name, :string

      # We are merging the events and conditions of an E-C-A (event-condition action) system
      # for now. Lets have a field for the type of trigger
      # for now, there is only one events: "scheduled"
      # we will add "message received" and the fields to it soon
      add :trigger_type, :string, default: "scheduled"

      # a contact and/or a group that is being triggered
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all)

      # the flow that is being triggered
      add :flow_id, references(:flows, on_delete: :delete_all)

      # lets add the time elements

      # start date and time of the condition
      # we combine the date and time from the frontend
      # to make calculations easy down the road and maintain
      # everything in UTC
      add :start_at, :utc_datetime, null: false

      # the optional end date of this trigger, the end date is inclusive
      add :end_date, :date, null: true

      # lets cache the last execution time and the next execution time
      # to make it easier to figure out which triggers to fire
      add :last_trigger_at, :utc_datetime, null: true
      add :next_trigger_at, :utc_datetime, null: true

      # is this a repeating trigger
      add :is_repeating, :boolean, default: false

      # if repeating, what is the repeat frequency
      # today | daily | weekly | monthly | weekday | weekend
      add :frequency, {:array, :string}, default: []

      # if weekly, the days that it repeats
      # 1 - Monday, 7 - Sunday (ISO date convention)
      add :days, {:array, :integer}, default: []

      # is this trigger still active, we disable triggers that have completed
      add :is_active, :boolean, default: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:triggers, :organization_id)
    create index(:triggers, :last_trigger_at)
    create index(:triggers, :next_trigger_at)
  end

  def trigger_logs() do
    create table(:trigger_logs) do
      # the batch that his belongs to
      add :trigger_id, references(:triggers, on_delete: :delete_all), null: false

      add :started_at, :utc_datetime, null: false
      add :flow_context_id, references(:flow_contexts, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
