defmodule Glific.Repo.Migrations.CreateFlowLabelTable do
  use Ecto.Migration

  def change do
    flow_labels()
  end

  @doc """
  Create flow label to associate flow messages with label
  """
  def flow_labels do
    create table(:flow_labels) do
      add :uuid, :uuid, null: false
      add :name, :string

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_labels, [:name, :organization_id])
  end
end
