defmodule Glific.Repo.Migrations.Batch do
  use Ecto.Migration

  # This migration assumes the default table name of "fun_with_flags_toggles"
  # is being used. If you have overriden that via configuration, you should
  # change this migration accordingly.

  def up do
    flow_batches()

    flow_batch_details()
  end

  def flow_batches() do
    create table(:flow_batches) do
      # the name to refer the extension
      add :name, :string, null: false

      # Optional start time if this is a time triggered batch
      add :start_at, :utc_datetime, null: true, default: nil

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_batches, [:name, :organization_id])
  end

  def flow_batch_details() do
    create table(:flow_batch_details) do
      # the sequencing number of this details in the batch
      add :number, :integer

      # the offset in time when this should execute relative to the previous one
      # The first entry for a batch will always have offset 0
      # the time difference in minutes
      add :offset, :integer, null: false

      # the flow that should be triggered when this detail is executed
      add :flow_id, references(:flow, on_delete: :delete_all), null: false

      add :flow_batch_id, references(:flow_batches, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end

  def flow_batch_contexts do
    create table(:flow_batch_contexts) do
      # we are executing either a contact OR a group
      add :contact_id, references(:contacts, on_delete: :delete_all)
      add :group_id, references(:group_id, on_delete: :delete_all)

      add :wakeup_at, :utc_datetime, null: true, default: nil

      # These are global times. When the batch context started and when it completed
      add :start_at, :utc_datetime, null: true, default: nil
      add :completed_at, :utc_datetime, null: true, default: nil

      add :flow_batch_detail_id, references(:flow_batch_detail, on_delete: :delete_all),
        null: false

      add :flow_batch_id, references(:flow_batches, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end

  def down do
    drop table(:flow_batch_contexts)
    drop table(:flow_batch_details)
    drop table(:flow_batches)
  end
end
