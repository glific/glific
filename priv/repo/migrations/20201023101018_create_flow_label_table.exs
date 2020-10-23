defmodule Glific.Repo.Migrations.CreateFlowLabelTable do
  use Ecto.Migration

  def change do
    flow_label()
  end


  @doc """
  Create flow label to associate flow messages with label
  """
  def flow_label do
    create table(:flow_label) do
      add :uuid, :uuid, null: false
      add :name, :string

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:flow_label, [:name, :organization_id])
  end
end
