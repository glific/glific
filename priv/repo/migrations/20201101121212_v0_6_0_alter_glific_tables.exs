defmodule Glific.Repo.Migrations.V0_6_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.0 Alter Glific tables
  """

  def change do
    flow_results()

    flow_revisions()
  end

  defp flow_revisions do
    alter table(:flow_revisions) do
      add :version, :integer, default: 0
    end
  end

  defp flow_results do
    # Create a table to store the values for a specific flow at a specific point in time
    # This is typically useful in a quiz scenario where we are collecting answers for different
    # questions across time
    create table(:flow_results) do
      # This is a key value map of the results saved during this flow run
      add :results, :map, default: %{}

      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      # We store flows with both id and uuid, since floweditor always refers to a flow by its uuid
      add :flow_uuid, :uuid, null: false

      # which specific published version are we referring to. This allows us to narrow
      # down the questions
      add :flow_version, :integer, default: 1, null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_results, [:contact_id, :flow_id, :flow_version])
    create index(:flow_results, [:contact_id, :organization_id])
  end
end
