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

      # start time of the trigger, if repeating event, start time of the first occurence
      add :start_at, :utc_datetime, null: false

      # is this a repeating trigger
      add :repeats, :boolean, default: false

      # if repeating, what is the repeat frequency
      # today | daily | weekly | weekday | weekend | mon | tue | ... | sat
      add :frequency, :string, default: "today"

      # the contact(s) to send this flow to
      # if we are sending to a bunch of contacts, they are stored in the
      # contacts_triggers join table below

      # the contacts in a group to send the flow to
      add :group_id, references(:groups, on_delete: :delete_all)

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
      add :trigger_id, references(:triggers, on_delete: :delete_all), null: false

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

      add :started_at, :utc_datetime, null: true, default: nil
      add :completed_at, :utc_datetime, null: true, default: nil

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
