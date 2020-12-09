defmodule Glific.Repo.Migrations.Trigger do
  use Ecto.Migration

  def up do
    trigger_actions()
    trigger_conditions()
    triggers()
    trigger_logs()
  end

  def down do
    drop table(:trigger_logs)
    drop table(:triggers)
    drop table(:trigger_actions)
    drop table(:trigger_conditions)
  end

  def trigger_actions() do
    create table(:trigger_actions) do
      # the name to refer the action (this might enable reuse)
      add :name, :string, null: false

      # the action type, for now the only action type is
      # start flow
      add :action_type, :string, default: "start_flow"

      # the contact(s) that are involved with this action
      # we store them in the join table below, to allow
      # multiple contacts to be associated with an action
      # this is when the contacts and group are determined statically

      # the contacts in a group to send the flow to
      add :group_id, references(:groups, on_delete: :delete_all)

      # should we act on the contact id (or context information) of the incoming event
      # this might be applicable in the context of an incoming message, you want to start
      # a flow with that contact id which is dynamic
      # We can add this later when we have a good use case
      # add :is_dynamic, :boolean, default: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end

  def trigger_conditions() do
    create table(:trigger_conditions) do
      # the name to refer the condition (this might enable reuse)
      add :name, :string, null: false

      # the below is for timed triggers only which we handle
      # everything else, we should call a custom function using MFA
      # (module-function-arguments)
      # this will be used for message received, will handle it when we have
      # a good use case

      # start time of the condition, if repeating condition, start time of the first occurence
      add :start_at, :utc_datetime, null: false

      # when will the next event be fired. The first value is the same as start_at
      # for one off triggers, this is not very useful
      # for repeating events, we figure out the next time this event should be fired
      add :fire_at, :utc_datetime

      # is this trigger still active, we disable triggers that have completed
      add :is_active, :boolean, default: true

      # is this a repeating trigger
      add :is_repeating, :boolean, default: false

      # if repeating, what is the repeat frequency
      # today | daily | weekly | weekday | weekend | mon | tue | ... | sat
      add :frequency, :string, default: "today"

      # if repeating trigger, we need an end date
      add :ends_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end
  end

  def triggers() do
    create table(:triggers) do
      # the name to refer the trigger
      add :name, :string, null: false

      # We are merging the events and conditions of an E-C-A (event-condition action) system
      # for now. Lets have a field for the type of event
      # for now, there are only two events: "scheduled" and "message received"
      add :event_type, :string, default: "scheduled"

      # foreign key to the trigger_condition that is part of this trigger
      add :trigger_condition_id, references(:trigger_conditions, on_delete: :delete_all),
        null: false

      # foreign key to the trigger_action that is part of this trigger
      add :trigger_action_id, references(:trigger_actions, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:triggers, [:name, :organization_id])
  end

  @doc """
  The join table between contacts and triggers
  """
  def contacts_triggers do
    create table(:contacts_triggers) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :trigger_action_id, references(:trigger_actions, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:contacts_triggers, [:trigger_id, :contact_id])
  end

  def trigger_logs() do
    create table(:trigger_logs) do
      # the batch that his belongs to
      add :trigger_id, references(:triggers, on_delete: :delete_all), null: false

      # the status of the flow
      # scheduled | completed | failed
      add :status, :string, null: false

      add :fire_at, :utc_datetime, null: false
      add :started_at, :utc_datetime, null: true, default: nil
      add :completed_at, :utc_datetime, null: true, default: nil

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
