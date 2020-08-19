defmodule Glific.Repo.Migrations.AddFlowCountsTable do
  use Ecto.Migration

  def change do
    create table(:flow_counts) do
      add :uuid, :uuid, null: false

      add :destination_uuid, :uuid, null: true

      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      add :flow_uuid, :uuid, null: false

      # Options are: node, exit, case
      add :type, :string

      add :count, :integer, default: 1

      add :recent_messages, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_counts, [:uuid, :flow_id, :type])
  end
end
