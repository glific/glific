defmodule Glific.Repo.Migrations.AddFlowCountsTable do
  use Ecto.Migration

  def change do
    create unique_index(:flows, :uuid)

    create table(:flow_counts) do
      add :uuid, :uuid, null: false

      add :destination_uuid, :uuid, null: true

      add :flow_uuid, references(:flows, column: :uuid, type: :uuid, on_delete: :delete_all),
        null: false

      # Options are: node, exit, case
      add :type, :string

      add :count, :integer, default: 1

      add :recent_messages, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_counts, [:uuid, :flow_uuid, :type])
  end
end
