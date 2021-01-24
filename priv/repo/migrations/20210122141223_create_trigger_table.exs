defmodule Glific.Repo.Migrations.Trigger do
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
    create table(:triggers) do
      # the name to refer the trigger
      add :name, :string, null: false

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

      # start time of the condition, if repeating condition, start time of the first occurence
      add :start_at, :utc_datetime, null: false

      # the optional end time of this trigger
      add :end_at, :utc_datetime, null: true

      # lets cache the last execution time and the next execution time
      # to make it easier to figure out which triggers to fire
      add :last_trigger_at, :utc_datetime, null: true
      add :next_trigger_at, :utc_datetime, null: true

      # is this a repeating trigger
      add :is_repeating, :boolean, default: false

      # if repeating, what is the repeat frequency
      # today | daily | weekly | monthly | weekday | weekend
      add :repeats, {:array, :string}, default: []

      # is this trigger still active, we disable triggers that have completed
      add :is_active, :boolean, default: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:triggers, [:name, :organization_id])
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
